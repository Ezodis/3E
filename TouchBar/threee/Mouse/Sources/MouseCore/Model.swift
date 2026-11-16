import Foundation

// Device-independent 3£ Mouse model. A device module (Devices/<Name>) turns a Profile into that
// mouse's reports; the window only shows what MouseCapabilities says the device supports.
// Windows twin: Windows/Mouse/MouseModel.cs.

public struct RGB: Codable, Equatable, Hashable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

public enum MouseButton: UInt8, CaseIterable, Codable, Identifiable {
    case left = 0, right = 1, middle = 2, back = 3, forward = 4
    public var id: UInt8 { rawValue }
    public var name: String { ["Left click", "Right click", "Middle click", "Back (MB4)", "Forward (MB5)"][Int(rawValue)] }
}

public enum MacroRepeat: UInt8, CaseIterable, Codable, Identifiable {
    case count = 1, whileHeld = 2, untilKeyPress = 4
    public var id: UInt8 { rawValue }
    public var name: String {
        switch self {
        case .count: return "Repeat N times"
        case .whileHeld: return "Loop while held"
        case .untilKeyPress: return "Loop until any key"
        }
    }
}

public enum MediaKey: String, CaseIterable, Codable, Identifiable {
    case next, previous, stop, playPause, mute, volumeUp, volumeDown
    case mediaPlayer, myComputer, mail, calculator
    case wwwSearch, wwwHome, wwwBack, wwwForward, wwwStop, wwwRefresh, wwwFavorites
    public var id: String { rawValue }
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

/// HID modifier bits (HID keyboard report order).
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

public enum ActionKind: String, CaseIterable, Codable, Identifiable {
    case mouse, doubleClick, tripleClick, key, fire, media, dpiUp, dpiDown, dpiLoop, dpiLock,
         switchPollingRate, switchLighting, disabled, macro, raw
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .mouse: return "Mouse button"
        case .doubleClick: return "Double click"
        case .tripleClick: return "Triple click"
        case .key: return "Key / combo"
        case .fire: return "Fire key (auto-repeat)"
        case .media: return "Multimedia"
        case .dpiUp: return "DPI +"
        case .dpiDown: return "DPI −"
        case .dpiLoop: return "DPI loop"
        case .dpiLock: return "DPI lock"
        case .switchPollingRate: return "Switch polling rate"
        case .switchLighting: return "Switch lighting effect"
        case .disabled: return "Disabled"
        case .macro: return "Macro"
        case .raw: return "Raw value"
        }
    }
}

/// What one button does, independent of any device's encoding.
public enum ButtonAction: Codable, Equatable, Hashable {
    case mouse(MouseButton)
    case doubleClick
    case tripleClick
    /// Single key or combination of HID keyboard usages (0 = none).
    case key(modifiers: Modifiers, key: UInt8, key2: UInt8)
    /// Repeats `key` (HID usage, or 0xF0…0xF4 for mouse buttons) `count` times every `intervalMs`.
    case fire(key: UInt8, intervalMs: UInt8, count: UInt8)
    case media(MediaKey)
    case dpiUp, dpiDown, dpiLoop
    case dpiLock(dpi: Int)
    case switchPollingRate
    case switchLighting
    case disabled
    /// Macro number (1-based).
    case macro(index: Int, mode: MacroRepeat)
    /// Device-specific value, kept verbatim.
    case raw(UInt32)

    public static func keyPress(_ usage: UInt8, modifiers: Modifiers = []) -> ButtonAction {
        .key(modifiers: modifiers, key: usage, key2: 0)
    }

    public var kind: ActionKind {
        switch self {
        case .mouse: return .mouse
        case .doubleClick: return .doubleClick
        case .tripleClick: return .tripleClick
        case .key: return .key
        case .fire: return .fire
        case .media: return .media
        case .dpiUp: return .dpiUp
        case .dpiDown: return .dpiDown
        case .dpiLoop: return .dpiLoop
        case .dpiLock: return .dpiLock
        case .switchPollingRate: return .switchPollingRate
        case .switchLighting: return .switchLighting
        case .disabled: return .disabled
        case .macro: return .macro
        case .raw: return .raw
        }
    }

    public var label: String {
        switch self {
        case .mouse(let b): return b.name
        case let .key(m, k, k2):
            var parts: [String] = []
            if !m.isDisjoint(with: [.leftControl, .rightControl]) { parts.append("⌃") }
            if !m.isDisjoint(with: [.leftOption, .rightOption]) { parts.append("⌥") }
            if !m.isDisjoint(with: [.leftShift, .rightShift]) { parts.append("⇧") }
            if !m.isDisjoint(with: [.leftCommand, .rightCommand]) { parts.append("⌘") }
            if k != 0 { parts.append(HIDKey.name(k)) }
            if k2 != 0 { parts.append("+ " + HIDKey.name(k2)) }
            return "Key: " + (parts.isEmpty ? "(none)" : parts.joined(separator: " "))
        case let .fire(k, i, c): return "Fire \(HIDKey.name(k)) ×\(c) every \(i) ms"
        case .media(let mk): return "Media: " + mk.name
        case .dpiLock(let d): return "DPI lock \(d)"
        case let .macro(i, m): return "Macro \(i) (\(m.name))"
        case .raw(let v): return String(format: "Raw 0x%08X", v)
        default: return kind.name
        }
    }
}

public struct MacroEvent: Codable, Equatable, Hashable, Identifiable {
    public var id = UUID()
    /// HID keyboard usage (0x04…0xE7) or 0xF0…0xF4 for mouse buttons.
    public var key: UInt8
    public var press: Bool
    /// Delay after this event, in ms.
    public var delayMs: Int
    public init(key: UInt8, press: Bool, delayMs: Int) { self.key = key; self.press = press; self.delayMs = delayMs }
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

    public static func tap(_ key: UInt8, holdMs: Int = 20, gapMs: Int = 20) -> [MacroEvent] {
        [MacroEvent(key: key, press: true, delayMs: holdMs), MacroEvent(key: key, press: false, delayMs: gapMs)]
    }
}

public struct DPIStage: Codable, Equatable {
    public var enabled: Bool
    public var x: Int
    public var y: Int
    /// Index into MouseCapabilities.dpiColorNames.
    public var color: Int
    public init(enabled: Bool, x: Int, y: Int? = nil, color: Int) {
        self.enabled = enabled; self.x = x; self.y = y ?? x; self.color = color
    }
}

/// Everything 3£ can configure on a mouse. Saved per device in ~/Library/Application Support/3E Mouse/<id>.json.
public struct Profile: Codable, Equatable {
    /// [mode][slot]
    public var buttons: [[ButtonAction]] = []
    public var macros: [Macro] = []
    public var stages: [DPIStage] = []
    public var currentStage = 0
    public var xyIndependent = false
    /// Index into MouseCapabilities.lightingEffects.
    public var effect = 0
    public var level = 4
    public var lightingRandom = false
    public var lightingColorCount = 0
    public var colors: [RGB] = []
    public var activeMode = 0
    /// Polling rate per mode (one entry when the device has no modes).
    public var ratesHz: [Int] = []

    public init() {}

    /// Pads a profile from an older/partial file to the shape the device needs.
    public func normalized(_ caps: MouseCapabilities, defaults: Profile) -> Profile {
        var p = self
        let modes = max(1, caps.modes)
        while p.buttons.count < modes {
            p.buttons.append(p.buttons.count < defaults.buttons.count ? defaults.buttons[p.buttons.count] : defaults.buttons.first ?? [])
        }
        for m in p.buttons.indices { while p.buttons[m].count < caps.slots { p.buttons[m].append(.disabled) } }
        while p.macros.count < caps.macroCount { p.macros.append(Macro(name: "Macro \(p.macros.count + 1)")) }
        while p.stages.count < caps.dpiStages {
            p.stages.append(p.stages.count < defaults.stages.count ? defaults.stages[p.stages.count] : DPIStage(enabled: false, x: caps.dpiValues.first ?? 800, color: 0))
        }
        if p.colors.count < caps.lightingColors { p.colors = defaults.colors }
        if p.ratesHz.count < modes { p.ratesHz = defaults.ratesHz }
        return p
    }
}

/// What a device supports. The window builds its pages from this, so a new mouse needs no UI changes.
public struct MouseCapabilities {
    public var slots = 0
    public var slotNames: [String] = []
    /// Hardware key modes (button layers). 1 = no mode switching.
    public var modes = 1
    public var actions: [ActionKind] = []
    public var mediaKeys: [MediaKey] = []
    public var mouseButtons: [MouseButton] = MouseButton.allCases
    /// Slot (1-based) of the extra side button offered "→ F13 / Pause" in one click. 0 = none.
    public var extraSideSlot = 0
    /// Slots "Identify buttons" may temporarily remap to F13… (1-based).
    public var identifySlots: [Int] = []

    public var dpiStages = 0
    public var dpiValues: [Int] = []
    public var dpiXY = false
    public var dpiColorNames: [String] = []
    /// Preview colours for dpiColorNames.
    public var dpiColorValues: [RGB] = []

    public var lightingEffects: [String] = []
    public var lightingEffectsHidden: Set<Int> = []
    public var lightingColors = 0
    public var lightingLevelMax = 0
    public var lightingRandom = false

    public var pollingRatesHz: [Int] = []

    public var macroCount = 0
    public var macroMaxDelayMs = 0
    public var macroBytes = 0

    // Vendor-style window (device-specific artwork and layout).
    /// Buttons shown in the key list and on the picture (vendor apps hide unused slots). 0 = all.
    public var visibleSlots = 0
    /// Skin file proving a vendor skin folder is complete (e.g. "main_nr.png").
    public var skinProbe: String?
    /// Folder or zip names of the vendor app, searched on this Mac to import its skin.
    public var skinSources: [String] = []
    /// Mouse picture inside the skin folder and its size.
    public var mousePicture: String?
    public var mousePictureSize = (width: 280.0, height: 440.0)
    /// Centre of each slot's number on the mouse picture (index = slot-1; nil = not on the picture).
    public var buttonHotspots: [(x: Double, y: Double)?] = []
    public var shownSlots: Int { visibleSlots > 0 ? min(visibleSlots, slots) : slots }

    public init() {}

    public var hasButtons: Bool { slots > 0 }
    public var hasDPI: Bool { dpiStages > 0 }
    public var hasLighting: Bool { !lightingEffects.isEmpty }
    public var hasPolling: Bool { !pollingRatesHz.isEmpty }
    public var hasMacros: Bool { macroCount > 0 && actions.contains(.macro) }
    public func slotName(_ slot: Int) -> String { slot - 1 < slotNames.count ? slotNames[slot - 1] : "Slot \(slot)" }
}

public struct MouseParts: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let dpi = MouseParts(rawValue: 1)
    public static let lighting = MouseParts(rawValue: 2)
    public static let polling = MouseParts(rawValue: 4)
    /// Button mapping and macros.
    public static let buttons = MouseParts(rawValue: 8)
    public static let all: MouseParts = [.dpi, .lighting, .polling, .buttons]
}

/// One supported mouse model. Implementations live in MouseHID/Devices/<Name>.
public protocol MouseDriver: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var capabilities: MouseCapabilities { get }
    func defaultProfile() -> Profile
    var log: (String) -> Void { get set }
    var isReady: Bool { get }
    /// Finds the device's configuration interface(s).
    @discardableResult func connect() -> Bool
    /// Loads whatever the device can report into the profile; returns a one-line status.
    func read(into profile: inout Profile) throws -> String
    func apply(_ profile: Profile, parts: MouseParts) throws
    /// Lines for the Device page (interfaces, raw reports).
    func diagnostics() -> [String]
}

/// A supported mouse: matched by USB VID/PID, created on demand.
public struct MouseDeviceEntry: Identifiable {
    public let id: String
    public let name: String
    public let vendorID: Int
    public let productID: Int
    public let make: () -> MouseDriver
    public init(id: String, name: String, vendorID: Int, productID: Int, make: @escaping () -> MouseDriver) {
        self.id = id; self.name = name; self.vendorID = vendorID; self.productID = productID; self.make = make
    }
}
