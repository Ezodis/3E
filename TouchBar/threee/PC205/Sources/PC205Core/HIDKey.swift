import Foundation

/// HID keyboard usage page (0x07) names, plus the firmware's mouse-button pseudo keys.
public enum HIDKey {
    public static let f13: UInt8 = 0x68
    public static let pause: UInt8 = 0x48

    public struct Entry: Identifiable, Hashable {
        public let usage: UInt8
        public let name: String
        public var id: UInt8 { usage }
    }

    public static let all: [Entry] = {
        var e: [Entry] = []
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { e.append(Entry(usage: UInt8(0x04 + i), name: String(c))) }
        for (i, c) in "1234567890".enumerated() { e.append(Entry(usage: UInt8(0x1E + i), name: String(c))) }
        let named: [(UInt8, String)] = [
            (0x28, "Return"), (0x29, "Escape"), (0x2A, "Backspace"), (0x2B, "Tab"), (0x2C, "Space"),
            (0x2D, "-"), (0x2E, "="), (0x2F, "["), (0x30, "]"), (0x31, "\\"), (0x33, ";"), (0x34, "'"),
            (0x35, "`"), (0x36, ","), (0x37, "."), (0x38, "/"), (0x39, "Caps Lock"),
        ]
        e += named.map { Entry(usage: $0.0, name: $0.1) }
        for i in 0..<12 { e.append(Entry(usage: UInt8(0x3A + i), name: "F\(i + 1)")) }
        let nav: [(UInt8, String)] = [
            (0x46, "Print Screen"), (0x47, "Scroll Lock"), (0x48, "Pause"), (0x49, "Insert"), (0x4A, "Home"),
            (0x4B, "Page Up"), (0x4C, "Delete"), (0x4D, "End"), (0x4E, "Page Down"), (0x4F, "→"),
            (0x50, "←"), (0x51, "↓"), (0x52, "↑"), (0x53, "Num Lock"), (0x54, "Keypad /"), (0x55, "Keypad *"),
            (0x56, "Keypad -"), (0x57, "Keypad +"), (0x58, "Keypad Enter"),
        ]
        e += nav.map { Entry(usage: $0.0, name: $0.1) }
        for i in 0..<9 { e.append(Entry(usage: UInt8(0x59 + i), name: "Keypad \(i + 1)")) }
        e.append(Entry(usage: 0x62, name: "Keypad 0"))
        e.append(Entry(usage: 0x63, name: "Keypad ."))
        e.append(Entry(usage: 0x65, name: "Menu"))
        for i in 0..<12 { e.append(Entry(usage: UInt8(0x68 + i), name: "F\(i + 13)")) }
        let mods: [(UInt8, String)] = [
            (0xE0, "Left Control"), (0xE1, "Left Shift"), (0xE2, "Left Option/Alt"), (0xE3, "Left Command/Win"),
            (0xE4, "Right Control"), (0xE5, "Right Shift"), (0xE6, "Right Option/Alt"), (0xE7, "Right Command/Win"),
            (0xF0, "Mouse Left"), (0xF1, "Mouse Right"), (0xF2, "Mouse Middle"),
            (0xF3, "Mouse Back"), (0xF4, "Mouse Forward"),
        ]
        e += mods.map { Entry(usage: $0.0, name: $0.1) }
        return e
    }()

    private static let byUsage: [UInt8: String] = Dictionary(all.map { ($0.usage, $0.name) }, uniquingKeysWith: { a, _ in a })

    public static func name(_ usage: UInt8) -> String {
        byUsage[usage] ?? String(format: "0x%02X", usage)
    }

    public static func usage(named n: String) -> UInt8? {
        if let e = all.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { return e.usage }
        if n.lowercased().hasPrefix("0x"), let v = UInt8(n.dropFirst(2), radix: 16) { return v }
        return nil
    }

    /// Usages the vendor's own VK→HID table can produce (0x005c6b10). Others may or may not be
    /// accepted by the host depending on the keyboard descriptor's logical maximum.
    public static func vendorTableContains(_ usage: UInt8) -> Bool {
        (0x04...0x65).contains(usage) || usage == 0x85 || usage == 0x87 || (0xE0...0xE7).contains(usage)
    }
}
