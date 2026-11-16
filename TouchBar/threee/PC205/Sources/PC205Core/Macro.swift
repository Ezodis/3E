import Foundation

public struct MacroEvent: Codable, Equatable, Hashable, Identifiable {
    public var id = UUID()
    /// HID keyboard usage (0x04…0xE7) or 0xF0 / 0xF1 / 0xF2 for left / right / middle mouse button.
    public var key: UInt8
    public var press: Bool
    /// Delay after this event, in ms (0…25627).
    public var delayMs: Int

    public init(key: UInt8, press: Bool, delayMs: Int) {
        self.key = key; self.press = press; self.delayMs = delayMs
    }

    private enum CodingKeys: String, CodingKey { case key, press, delayMs }
}

public struct Macro: Codable, Equatable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var events: [MacroEvent]
    /// Used when the button's repeat mode is `.count`.
    public var repeatCount: UInt16

    public init(name: String, events: [MacroEvent] = [], repeatCount: UInt16 = 1) {
        self.name = name; self.events = events; self.repeatCount = repeatCount
    }

    private enum CodingKeys: String, CodingKey { case name, events, repeatCount }

    public static let maxDelay = 0x641B

    /// 128-byte firmware buffer (MacProtocol=2). See PROTOCOL.md §5.
    public func encode() -> [UInt8] {
        let size = PC205.macroSize
        var out = [UInt8](repeating: 0, count: size)
        let rc = repeatCount == 0 ? 1 : repeatCount
        out[0] = UInt8(rc >> 8)
        out[1] = UInt8(rc & 0xFF)
        var i = 2
        for e in events {
            let delay = max(0, min(Macro.maxDelay, e.delayMs))
            let long = delay > 0x7F
            let limit = long ? size - 5 : size - 3
            if i >= limit { break }
            let flag: UInt8 = e.press ? 0x80 : 0x00
            if long {
                out[i] = flag | UInt8(delay % 100)
                out[i + 1] = e.key
                out[i + 2] = UInt8(delay / 100)
                out[i + 3] = 0x03
                i += 4
            } else {
                out[i] = flag | UInt8(delay == 0 ? 1 : delay)
                out[i + 1] = e.key
                i += 2
            }
        }
        out[i] = 0
        out[i + 1] = 0
        return out
    }

    public static func decode(_ b: [UInt8], name: String) -> Macro {
        var m = Macro(name: name, events: [], repeatCount: UInt16(b[0]) << 8 | UInt16(b[1]))
        var i = 2
        while i + 1 < b.count {
            let f = b[i], k = b[i + 1]
            if f == 0 && k == 0 { break }
            if i + 3 < b.count && b[i + 3] == 0x03 && (f & 0x7F) < 100 && b[i + 2] > 0 {
                m.events.append(MacroEvent(key: k, press: f & 0x80 != 0, delayMs: Int(f & 0x7F) + 100 * Int(b[i + 2])))
                i += 4
            } else {
                m.events.append(MacroEvent(key: k, press: f & 0x80 != 0, delayMs: Int(f & 0x7F)))
                i += 2
            }
        }
        return m
    }

    /// Convenience: tap a key (press, delay, release, delay).
    public static func tap(_ key: UInt8, holdMs: Int = 20, gapMs: Int = 20) -> [MacroEvent] {
        [MacroEvent(key: key, press: true, delayMs: holdMs), MacroEvent(key: key, press: false, delayMs: gapMs)]
    }
}
