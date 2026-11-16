import Foundation
import SwiftUI
import AppKit
import PC205Core
import PC205HID

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: Profile
    @Published var connected = false
    @Published var status = "Not connected"
    @Published var logLines: [String] = []
    @Published var editingMode = 0
    @Published var identifyResult: String?
    @Published var identifying = false
    @Published var lastGeneral: GeneralReport?

    let device = PC205Device()
    private let store: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3E Mouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = dir.appendingPathComponent("profile.json")
        if let d = try? Data(contentsOf: store), let p = try? JSONDecoder().decode(Profile.self, from: d) {
            profile = p
        } else {
            profile = .lolDefault
        }
        device.log = { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        }
        connect()
    }

    func appendLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    func save() {
        if let d = try? JSONEncoder().encode(profile) { try? d.write(to: store) }
    }

    func connect() {
        connected = device.connect()
        if connected {
            status = "Connected"
            readFromMouse()
        } else if device.transport.isConnected {
            status = "Mouse found, but the configuration interface did not answer (see Device tab)"
        } else {
            status = "PC205 not found – plug it in and press Reconnect"
        }
    }

    func readFromMouse() {
        do {
            let g = try device.readGeneral()
            lastGeneral = g
            profile.load(from: g)
            if let m = try device.readMode() { profile.load(from: m) }
            if let x = device.readMatrix() {
                profile.load(matrixPayload: x)
                appendLog("matrix read back from mouse")
            } else {
                appendLog("matrix cannot be read back (normal; the vendor app doesn't read it either) – using saved profile")
            }
            status = "Connected – read settings (sensor \(PC205.sensorNames[g.sensorCode] ?? String(g.sensorCode)), signature \(g.signatureOK ? "OK" : "unexpected"))"
        } catch {
            status = "Read failed: \(error)"
        }
    }

    func apply(_ parts: PC205Device.ApplyParts = .all) {
        save()
        do {
            try device.apply(profile, parts: parts)
            status = "Applied to mouse at \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            status = "Apply failed: \(error)"
        }
    }

    // MARK: Identify buttons

    /// F13…F19 → macOS virtual key codes.
    static let identifyKeys: [(usage: UInt8, vk: UInt16)] = [
        (0x68, 105), (0x69, 107), (0x6A, 113), (0x6B, 106), (0x6C, 64), (0x6D, 79), (0x6E, 80),
    ]
    /// Slots temporarily remapped while identifying (left/right/middle stay untouched).
    static let identifySlots = Array(4...10)
    private var monitor: Any?

    func startIdentify() {
        var temp = profile
        for (i, slot) in Self.identifySlots.enumerated() {
            for m in 0..<PC205.modes { temp.buttons[m][slot - 1] = .keyPress(Self.identifyKeys[i].usage) }
        }
        do {
            try device.apply(temp, parts: .matrix)
        } catch {
            status = "Identify failed: \(error)"
            return
        }
        identifying = true
        identifyResult = "Press each side / top button while this window is focused…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self else { return ev }
            if let idx = Self.identifyKeys.firstIndex(where: { $0.vk == ev.keyCode }) {
                let slot = Self.identifySlots[idx]
                self.identifyResult = "That button is slot \(slot) (\(Profile.slotNames[slot - 1]))."
                return nil
            }
            return ev
        }
    }

    func stopIdentify() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        identifying = false
        apply(.matrix)
        identifyResult = (identifyResult ?? "") + " Original mapping restored."
    }

    func exportProfile(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(profile).write(to: url)
    }

    func importProfile(from url: URL) throws {
        profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
        save()
    }
}
