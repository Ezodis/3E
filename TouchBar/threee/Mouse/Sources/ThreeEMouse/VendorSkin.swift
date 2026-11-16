import AppKit
import Foundation

/// Vendor skin images for the 3£ Mouse window. 3£ does not ship the vendor's artwork (the repo is
/// public): it copies the skins from the user's own copy of the vendor app (its zip or skins folder)
/// into ~/Library/Application Support/3E Mouse/skins/<device>. Without them the same layout is drawn.
/// Windows twin: Windows/Mouse/VendorSkin.cs.
struct VendorSkin {
    let folder: URL
    private static var cache: [URL: NSImage] = [:]

    static func store(_ deviceID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3E Mouse/skins/\(deviceID)", isDirectory: true)
    }

    static func load(_ deviceID: String, probe: String) -> VendorSkin? {
        let dir = store(deviceID)
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(probe).path) ? VendorSkin(folder: dir) : nil
    }

    func image(_ relative: String?) -> NSImage? {
        guard let relative else { return nil }
        let url = folder.appendingPathComponent(relative.replacingOccurrences(of: "\\", with: "/"))
        if let hit = Self.cache[url] { return hit }
        guard let img = NSImage(contentsOf: url) else { return nil }
        // Vendor PNGs are 72/96 dpi bitmaps; show them 1 point per pixel like the original window.
        if let rep = img.representations.first { img.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
        Self.cache[url] = img
        return img
    }

    /// Imports from a zip of the vendor app, its folder, or its skins folder.
    static func importFrom(_ source: URL, deviceID: String, probe: String) throws -> VendorSkin {
        let fm = FileManager.default
        let target = store(deviceID)
        let work = fm.temporaryDirectory.appendingPathComponent("3e-mouse-skin-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        var root = source
        if source.pathExtension.lowercased() == "zip" {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", source.path, work.path]
            try p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw NSError(domain: "3E Mouse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not unzip \(source.lastPathComponent)"]) }
            root = work
        }
        guard let skins = findSkins(in: root, probe: probe) else {
            throw NSError(domain: "3E Mouse", code: 2, userInfo: [NSLocalizedDescriptionKey: "No vendor skins (\(probe)) in \(source.lastPathComponent)"])
        }
        let staged = work.appendingPathComponent("staged")
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        if let e = fm.enumerator(at: skins, includingPropertiesForKeys: nil) {
            for case let f as URL in e where ["png", "bmp"].contains(f.pathExtension.lowercased()) {
                let rel = f.path.dropFirst(skins.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let dest = staged.appendingPathComponent(rel)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: f, to: dest)
            }
        }
        try? fm.removeItem(at: target)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staged, to: target)
        cache.removeAll()
        return VendorSkin(folder: target)
    }

    private static func findSkins(in root: URL, probe: String) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent(probe).path) { return root }
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let f as URL in e where f.lastPathComponent == probe { return f.deletingLastPathComponent() }
        return nil
    }

    /// Looks for the vendor zip/folder in the usual places (never installs or runs anything).
    static func autoImport(_ deviceID: String, probe: String, sources: [String]) -> VendorSkin? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = ["Downloads", "Desktop", "Documents", "source", "eduu", "source/eduu", ""].map { home.appendingPathComponent($0) }
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for item in items where sources.contains(where: { item.lastPathComponent.localizedCaseInsensitiveContains($0) }) {
                if let s = try? importFrom(item, deviceID: deviceID, probe: probe) { return s }
            }
        }
        return nil
    }
}
