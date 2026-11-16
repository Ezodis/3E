import Foundation
import SwiftUI
import AppKit
import MouseCore
import MouseHID

/// Device-independent state for the 3£ Mouse window: detects supported mice, keeps one
/// profile per device and talks only to the MouseDriver protocol.
@MainActor
final class AppModel: ObservableObject {
    @Published var detected: [MouseDeviceEntry] = []
    @Published var selectedID: String?
    @Published private(set) var driver: MouseDriver?
    @Published var profile = Profile()
    @Published var status = "Looking for a supported mouse…"
    @Published var logLines: [String] = []
    @Published var editingMode = 0
    @Published var identifyResult: String?
    @Published var identifying = false

    private let folder: URL
    private var monitor: Any?

    var caps: MouseCapabilities { driver?.capabilities ?? MouseCapabilities() }
    var connected: Bool { driver?.isReady == true }

    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3E Mouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        connect()
    }

    private func profileURL(_ id: String) -> URL { folder.appendingPathComponent("\(id).json") }

    func appendLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    func save() {
        guard let d = driver, let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: profileURL(d.id))
    }

    func connect() {
        detected = MouseDevices.detect()
        guard let entry = detected.first(where: { $0.id == selectedID }) ?? detected.first else {
            driver = nil
            status = "No supported mouse connected. Supported: " + MouseDevices.supported.map(\.name).joined(separator: ", ") + "."
            return
        }
        selectedID = entry.id
        let d = entry.make()
        d.log = { [weak self] line in Task { @MainActor in self?.appendLog(line) } }
        driver = d
        let defaults = d.defaultProfile()
        if let data = try? Data(contentsOf: profileURL(d.id)), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = p.normalized(d.capabilities, defaults: defaults)
        } else {
            profile = defaults.normalized(d.capabilities, defaults: defaults)
        }
        editingMode = 0
        if d.connect() {
            status = "\(d.displayName) connected"
            readFromMouse()
        } else {
            status = "\(d.displayName) found, but its configuration interface did not answer (see Device tab)"
        }
    }

    func readFromMouse() {
        guard let d = driver, d.isReady else { return }
        do {
            let summary = try d.read(into: &profile)
            status = "\(d.displayName) – \(summary)"
        }
        catch { status = "Read failed: \(error)" }
    }

    func apply(_ parts: MouseParts = .all) {
        guard let d = driver else { return }
        save()
        guard d.isReady else { status = "Saved. The mouse is not connected – press Reconnect."; return }
        if caps.hasDPI && !profile.stages.contains(where: \.enabled) { profile.stages[0].enabled = true }
        do {
            try d.apply(profile, parts: parts)
            status = "Applied to \(d.displayName) at \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            status = "Apply failed: \(error)"
        }
    }

    func setSideKey(_ usage: UInt8) {
        guard caps.extraSideSlot > 0 else { return }
        for m in profile.buttons.indices { profile.buttons[m][caps.extraSideSlot - 1] = .keyPress(usage) }
        apply(.buttons)
    }

    func resetToDefaults() {
        guard let d = driver else { return }
        profile = d.defaultProfile().normalized(d.capabilities, defaults: d.defaultProfile())
    }

    // MARK: Identify buttons

    /// F13…F24 → macOS virtual key codes.
    static let functionKeyCodes: [UInt16] = [105, 107, 113, 106, 64, 79, 80, 90, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF]

    func startIdentify() {
        guard let d = driver, d.isReady else { status = "Connect the mouse first."; return }
        let slots = Array(caps.identifySlots.prefix(8))
        var temp = profile
        for (i, slot) in slots.enumerated() {
            for m in temp.buttons.indices { temp.buttons[m][slot - 1] = .keyPress(HIDKey.f13 + UInt8(i)) }
        }
        do { try d.apply(temp, parts: .buttons) } catch { status = "Identify failed: \(error)"; return }
        identifying = true
        identifyResult = "Press each mouse button while this window is focused…"
        let caps = self.caps
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, let idx = Self.functionKeyCodes.firstIndex(of: ev.keyCode), idx < slots.count else { return ev }
            self.identifyResult = "That button is \(caps.slotName(slots[idx]))."
            return nil
        }
    }

    func stopIdentify() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        identifying = false
        apply(.buttons)
        identifyResult = (identifyResult ?? "") + " Original mapping restored."
    }

    func exportProfile(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(profile).write(to: url)
    }

    func importProfile(from url: URL) throws {
        guard let d = driver else { return }
        profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url)).normalized(d.capabilities, defaults: d.defaultProfile())
        save()
    }
}
