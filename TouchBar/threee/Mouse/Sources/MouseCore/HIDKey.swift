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

    /// macOS virtual key code (NSEvent.keyCode) → HID usage (0 = unknown). For key capture and macro recording.
    public static func fromMacKeyCode(_ code: UInt16) -> UInt8 { macKeyCodes[code] ?? 0 }

    /// HID usage of a modifier key → its bit in the modifier byte (0 if not a modifier).
    public static func modifierBit(_ usage: UInt8) -> UInt8 { (0xE0...0xE7).contains(usage) ? 1 << (usage - 0xE0) : 0 }

    static let macKeyCodes: [UInt16: UInt8] = [
        0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A, 6: 0x1D, 7: 0x1B, 8: 0x06, 9: 0x19, 11: 0x05, 12: 0x14,
        13: 0x1A, 14: 0x08, 15: 0x15, 16: 0x1C, 17: 0x17, 18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22,
        24: 0x2E, 25: 0x26, 26: 0x24, 27: 0x2D, 28: 0x25, 29: 0x27, 30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2F, 34: 0x0C,
        35: 0x13, 36: 0x28, 37: 0x0F, 38: 0x0D, 39: 0x34, 40: 0x0E, 41: 0x33, 42: 0x31, 43: 0x36, 44: 0x38, 45: 0x11,
        46: 0x10, 47: 0x37, 48: 0x2B, 49: 0x2C, 50: 0x35, 51: 0x2A, 53: 0x29, 54: 0xE7, 55: 0xE3, 56: 0xE1, 57: 0x39,
        58: 0xE2, 59: 0xE0, 60: 0xE5, 61: 0xE6, 62: 0xE4, 64: 0x6C, 65: 0x63, 67: 0x55, 69: 0x57, 71: 0x53, 75: 0x54,
        76: 0x58, 78: 0x56, 79: 0x6D, 80: 0x6E, 81: 0x67, 82: 0x62, 83: 0x59, 84: 0x5A, 85: 0x5B, 86: 0x5C, 87: 0x5D,
        88: 0x5E, 89: 0x5F, 90: 0x6F, 91: 0x60, 92: 0x61, 96: 0x3E, 97: 0x3F, 98: 0x40, 99: 0x3C, 100: 0x41, 101: 0x42,
        103: 0x44, 105: 0x68, 106: 0x6B, 107: 0x69, 109: 0x43, 111: 0x45, 113: 0x6A, 114: 0x49, 115: 0x4A, 116: 0x4B,
        117: 0x4C, 118: 0x3D, 119: 0x4D, 120: 0x3B, 121: 0x4E, 122: 0x3A, 123: 0x50, 124: 0x4F, 125: 0x51, 126: 0x52,
    ]
}
