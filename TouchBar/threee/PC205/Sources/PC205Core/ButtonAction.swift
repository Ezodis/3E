import Foundation

public enum MouseButton: UInt8, CaseIterable, Codable, Identifiable {
    case left = 0, right = 1, middle = 2, back = 3, forward = 4
    public var id: UInt8 { rawValue }
    public var name: String { ["Left click", "Right click", "Middle click", "Back (MB4)", "Forward (MB5)"][Int(rawValue)] }
}

public enum MacroRepeat: UInt8, CaseIterable, Codable, Identifiable {
    case count = 1          // repeat N times (N stored in the macro buffer)
    case whileHeld = 2      // loop until the button is released
    case untilKeyPress = 4  // loop until any key is pressed
    public var id: UInt8 { rawValue }
    public var name: String {
        switch self {
        case .count: return "Repeat N times"
        case .whileHeld: return "Loop while held"
        case .untilKeyPress: return "Loop until any key"
        }
    }
}

/// Consumer-control ("multimedia") functions supported by the firmware bitmap encoding.
public enum MediaKey: String, CaseIterable, Codable, Identifiable {
    case next, previous, stop, playPause, mute, volumeUp, volumeDown
    case mediaPlayer, myComputer, mail, calculator
    case wwwSearch, wwwHome, wwwBack, wwwForward, wwwStop, wwwRefresh, wwwFavorites
    public var id: String { rawValue }

    /// (byte index 1…3, bit)
    var bit: (Int, UInt8) {
        switch self {
        case .next: return (1, 0x01)
        case .previous: return (1, 0x02)
        case .stop: return (1, 0x04)
        case .playPause: return (1, 0x08)
        case .mute: return (1, 0x10)
        case .volumeUp: return (1, 0x40)
        case .volumeDown: return (1, 0x80)
        case .mediaPlayer: return (2, 0x01)
        case .myComputer: return (2, 0x02)
        case .mail: return (2, 0x10)
        case .calculator: return (2, 0x20)
        case .wwwSearch: return (3, 0x01)
        case .wwwHome: return (3, 0x02)
        case .wwwBack: return (3, 0x04)
        case .wwwForward: return (3, 0x08)
        case .wwwStop: return (3, 0x10)
        case .wwwRefresh: return (3, 0x20)
        case .wwwFavorites: return (3, 0x40)
        }
    }

    public var name: String {
        switch self {
        case .next: return "Next track"
        case .previous: return "Previous track"
        case .stop: return "Stop"
        case .playPause: return "Play / Pause"
        case .mute: return "Mute"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mediaPlayer: return "Media player"
        case .myComputer: return "My Computer"
        case .mail: return "Mail"
        case .calculator: return "Calculator"
        case .wwwSearch: return "Web search"
        case .wwwHome: return "Web home"
        case .wwwBack: return "Web back"
        case .wwwForward: return "Web forward"
        case .wwwStop: return "Web stop"
        case .wwwRefresh: return "Web refresh"
        case .wwwFavorites: return "Web favourites"
        }
    }
}

/// HID modifier bits (same order as the HID keyboard report and the firmware).
public struct Modifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let leftControl = Modifiers(rawValue: 0x01)
    public static let leftShift = Modifiers(rawValue: 0x02)
    public static let leftOption = Modifiers(rawValue: 0x04)
    public static let leftCommand = Modifiers(rawValue: 0x08)
    public static let rightControl = Modifiers(rawValue: 0x10)
    public static let rightShift = Modifiers(rawValue: 0x20)
    public static let rightOption = Modifiers(rawValue: 0x40)
    public static let rightCommand = Modifiers(rawValue: 0x80)
}

/// What a mouse button does. Encodes to / decodes from the 32-bit firmware key entry
/// (without the slot-index nibble). See PROTOCOL.md §5.
public enum ButtonAction: Codable, Equatable, Hashable {
    case mouse(MouseButton)
    case doubleClick
    case tripleClick
    /// Single key or key combination: HID keyboard usages (0 = none).
    case key(modifiers: Modifiers, key: UInt8, key2: UInt8)
    /// Repeats `key` (HID usage or 0xF0…0xF4 for mouse buttons) `count` times every `intervalMs`.
    case fire(key: UInt8, intervalMs: UInt8, count: UInt8)
    case media(MediaKey)
    case dpiUp, dpiDown, dpiLoop
    case dpiLock(dpi: Int)
    case switchPollingRate
    case switchLighting
    case disabled
    /// Macro buffer 1…8.
    case macro(index: Int, mode: MacroRepeat)
    /// Unknown entry, kept verbatim.
    case raw(UInt32)

    public static func keyPress(_ usage: UInt8, modifiers: Modifiers = []) -> ButtonAction {
        .key(modifiers: modifiers, key: usage, key2: 0)
    }

    public func encode() -> UInt32 {
        switch self {
        case .mouse(let b): return 0xF010 | (UInt32(b.rawValue) << 8)
        case .doubleClick: return 0x0232_F020
        case .tripleClick: return 0x0130
        case let .key(m, k, k2):
            return 0x60 | UInt32(m.rawValue) << 8 | UInt32(k) << 16 | UInt32(k2) << 24
        case let .fire(k, i, c):
            return 0x20 | UInt32(k) << 8 | UInt32(i) << 16 | UInt32(c) << 24
        case .media(let mk):
            let (byte, bit) = mk.bit
            return 0x70 | UInt32(bit) << (8 * byte)
        case .dpiLoop: return 0x0040
        case .dpiUp: return 0x2040
        case .dpiDown: return 0x4040
        case .dpiLock(let dpi): return 0x8040 | UInt32(PC205.dpiCode(for: dpi) & 0x0F) << 8
        case .disabled: return 0x0150
        case .switchPollingRate: return 0x0250
        case .switchLighting: return 0x0750
        case let .macro(idx, mode):
            return 0x90 | UInt32(mode.rawValue) << 8 | UInt32(idx & 0x0F) << 12
        case .raw(let v): return v & 0xFFFF_FFF0
        }
    }

    /// Entry as stored in the matrix: action | slot (1…10) in the low nibble (KeyCodeHasIndex=1).
    public func entry(slot: Int) -> UInt32 { (encode() & 0xFFFF_FFF0) | UInt32(slot & 0x0F) }

    public static func decode(_ entry: UInt32) -> ButtonAction {
        let v = entry & 0xFFFF_FFF0
        let b0 = UInt8(v & 0xF0)
        let b1 = UInt8((v >> 8) & 0xFF), b2 = UInt8((v >> 16) & 0xFF), b3 = UInt8((v >> 24) & 0xFF)
        switch b0 {
        case 0x10 where b2 == 0 && b3 == 0 && b1 & 0xF0 == 0xF0:
            if let mb = MouseButton(rawValue: b1 & 0x0F) { return .mouse(mb) }
        case 0x20:
            if v == 0x0232_F020 { return .doubleClick }
            return .fire(key: b1, intervalMs: b2, count: b3)
        case 0x30 where v == 0x0130: return .tripleClick
        case 0x40:
            switch v {
            case 0x0040: return .dpiLoop
            case 0x2040: return .dpiUp
            case 0x4040: return .dpiDown
            default:
                if b1 & 0x80 != 0, let dpi = PC205.dpi(forCode: b1 & 0x0F) { return .dpiLock(dpi: dpi) }
            }
        case 0x50:
            switch v {
            case 0x0150: return .disabled
            case 0x0250: return .switchPollingRate
            case 0x0750: return .switchLighting
            default: break
            }
        case 0x60: return .key(modifiers: Modifiers(rawValue: b1), key: b2, key2: b3)
        case 0x70:
            for mk in MediaKey.allCases where mk.encode() == v { return .media(mk) }
        case 0x90:
            if let mode = MacroRepeat(rawValue: b1 & 0x0F) { return .macro(index: Int(b1 >> 4), mode: mode) }
        default: break
        }
        return .raw(v)
    }

    public var label: String {
        switch self {
        case .mouse(let b): return b.name
        case .doubleClick: return "Double click"
        case .tripleClick: return "Triple click"
        case let .key(m, k, k2):
            var parts: [String] = []
            if m.contains(.leftControl) || m.contains(.rightControl) { parts.append("⌃") }
            if m.contains(.leftOption) || m.contains(.rightOption) { parts.append("⌥") }
            if m.contains(.leftShift) || m.contains(.rightShift) { parts.append("⇧") }
            if m.contains(.leftCommand) || m.contains(.rightCommand) { parts.append("⌘") }
            if k != 0 { parts.append(HIDKey.name(k)) }
            if k2 != 0 { parts.append("+ " + HIDKey.name(k2)) }
            return "Key: " + (parts.isEmpty ? "(none)" : parts.joined(separator: " "))
        case let .fire(k, i, c): return "Fire \(HIDKey.name(k)) ×\(c) every \(i) ms"
        case .media(let mk): return "Media: " + mk.name
        case .dpiUp: return "DPI +"
        case .dpiDown: return "DPI −"
        case .dpiLoop: return "DPI loop"
        case .dpiLock(let d): return "DPI lock \(d)"
        case .switchPollingRate: return "Switch polling rate"
        case .switchLighting: return "Switch lighting effect"
        case .disabled: return "Disabled"
        case let .macro(i, m): return "Macro \(i) (\(m.name))"
        case .raw(let v): return String(format: "Raw 0x%08X", v)
        }
    }
}

extension MediaKey {
    func encode() -> UInt32 { ButtonAction.media(self).encode() }
}
