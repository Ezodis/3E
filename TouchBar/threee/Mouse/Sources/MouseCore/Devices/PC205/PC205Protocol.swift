import Foundation

// Thunderbird PC205 (Sinowealth 258A:1007, "8832" firmware, MsFw=7): capabilities and encoding.
// Pure code (tested by MouseCoreTests). Specification: Shared/PC205/PROTOCOL.md.
// Windows twin: Windows/Mouse/Devices/PC205/PC205Protocol.cs.

public enum PC205 {
    public static let id = "pc205"
    public static let name = "Thunderbird PC205"
    public static let vendorID = 0x258A
    public static let productID = 0x1007
    public static let vendorUsagePage = 0xFF00

    public static let generalReportID: UInt8 = 4
    public static let generalPayload = 58          // feature length 59 incl. report ID
    public static let matrixReportID: UInt8 = 6
    public static let matrixPayload = 0x478        // feature length 1145 incl. report ID
    public static let modeReportID: UInt8 = 8
    public static let modePayload = 8              // feature length 9 incl. report ID

    public static let slots = 10
    public static let modes = 3
    public static let dpiStages = 8
    public static let macroCount = 8
    public static let macroSize = 128
    public static let macroAreaSize = macroCount * macroSize
    public static let macroMaxDelay = 0x641B
    public static let extraSideSlot = 8

    /// DPISET from Cfg.ini; hardware code = index + 1.
    public static let dpiTable: [Int] = [500, 800, 1000, 1200, 1600, 2000, 2400, 3000,
                                         3200, 3500, 4000, 4500, 5000, 5500, 6000, 7200]
    public static let pollingHz = [125, 250, 500, 1000]   // codes 1…4
    /// Device signature from Cfg.ini PSD (= "FR2763").
    public static let signature: [UInt8] = [0x46, 0x52, 0x32, 0x37, 0x36, 0x33]
    public static let sensorNames: [UInt8: String] = [
        1: "0x5050", 2: "0x3050", 3: "0x9800", 4: "0x3320", 5: "0x3330", 6: "0x3360",
        7: "0x3610", 8: "PMW3212 (0x3212)", 9: "0x3310", 11: "0x3325", 12: "0x7350", 14: "0x3327",
    ]

    public static let capabilities: MouseCapabilities = {
        var c = MouseCapabilities()
        c.slots = slots
        c.slotNames = ["Slot 1 – Left", "Slot 2 – Right", "Slot 3 – Middle (wheel)", "Slot 4 – Back (MB4)",
                       "Slot 5 – Forward (MB5)", "Slot 6 – DPI +", "Slot 7 – DPI −",
                       "Slot 8 – Extra side button?", "Slot 9", "Slot 10"]
        c.modes = modes
        c.actions = ActionKind.allCases
        c.mediaKeys = MediaKey.allCases
        c.extraSideSlot = extraSideSlot
        c.identifySlots = Array(4...10)
        c.dpiStages = dpiStages
        c.dpiValues = dpiTable
        c.dpiXY = true
        c.dpiColorNames = ["None", "Red", "Green", "Blue", "Cyan", "Yellow", "Magenta", "White"]
        c.dpiColorValues = [RGB(0, 0, 0), RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255), RGB(0, 255, 255),
                            RGB(255, 255, 0), RGB(255, 0, 255), RGB(255, 255, 255)]
        c.lightingEffects = ["Colorful Streaming", "Steady", "Breathing", "Tail", "Neon", "Colorful Steady", "Flicker",
                             "Response", "Streaming", "Wave", "Trailing", "Off (None)"]
        c.lightingEffectsHidden = [5, 6, 8, 10]   // LedMask=0x560
        c.lightingColors = 7
        c.lightingLevelMax = 8
        c.lightingRandom = true
        c.pollingRatesHz = pollingHz
        c.macroCount = macroCount
        c.macroMaxDelayMs = macroMaxDelay
        c.macroBytes = macroSize
        return c
    }()

    public static func dpiCode(for dpi: Int) -> UInt8 {
        let i = dpiTable.enumerated().min { abs($0.element - dpi) < abs($1.element - dpi) }!.offset
        return UInt8(i + 1)
    }
    public static func dpi(forCode code: UInt8) -> Int? {
        let i = Int(code & 0x7F) - 1
        return dpiTable.indices.contains(i) ? dpiTable[i] : nil
    }

    /// Vendor Cfg.ini defaults (K1…K10, DPI, DC, DR) plus the extra side button sending F13
    /// (3£ LoL Kalista kite key) when `lolSideKey`.
    public static func defaultProfile(lolSideKey: Bool = true) -> Profile {
        let row: [ButtonAction] = [
            .mouse(.left), .mouse(.right), .mouse(.middle), .mouse(.back), .mouse(.forward),
            .dpiUp, .dpiDown, lolSideKey ? .keyPress(HIDKey.f13) : .tripleClick, .switchLighting, .switchLighting,
        ]
        let dpis = [1200, 2400, 3500, 5500, 7200, 7200, 7200, 7200]
        let cols = [1, 3, 2, 6, 5, 7, 7, 7]
        var p = Profile()
        p.buttons = Array(repeating: row, count: modes)
        p.macros = (1...macroCount).map { Macro(name: "Macro \($0)") }
        p.stages = (0..<dpiStages).map { DPIStage(enabled: $0 < 5, x: dpis[$0], color: cols[$0]) }
        p.currentStage = 1
        p.effect = 2
        p.level = 4
        p.colors = [RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255), RGB(255, 255, 0),
                    RGB(0, 255, 255), RGB(255, 0, 255), RGB(255, 255, 255)]
        p.ratesHz = [500, 500, 500]
        return p
    }
}

/// ButtonAction / Macro ⇄ PC205 firmware bytes (PROTOCOL.md §5).
public enum PC205Codec {
    /// (byte index 1…3, bit)
    static func mediaBit(_ m: MediaKey) -> (Int, UInt8) {
        switch m {
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

    public static func encode(_ a: ButtonAction) -> UInt32 {
        switch a {
        case .mouse(let b): return 0xF010 | (UInt32(b.rawValue) << 8)
        case .doubleClick: return 0x0232_F020
        case .tripleClick: return 0x0130
        case let .key(m, k, k2): return 0x60 | UInt32(m.rawValue) << 8 | UInt32(k) << 16 | UInt32(k2) << 24
        case let .fire(k, i, c): return 0x20 | UInt32(k) << 8 | UInt32(i) << 16 | UInt32(c) << 24
        case .media(let mk):
            let (byte, bit) = mediaBit(mk)
            return 0x70 | UInt32(bit) << (8 * byte)
        case .dpiLoop: return 0x0040
        case .dpiUp: return 0x2040
        case .dpiDown: return 0x4040
        case .dpiLock(let dpi): return 0x8040 | UInt32(PC205.dpiCode(for: dpi) & 0x0F) << 8
        case .disabled: return 0x0150
        case .switchPollingRate: return 0x0250
        case .switchLighting: return 0x0750
        case let .macro(idx, mode): return 0x90 | UInt32(mode.rawValue) << 8 | UInt32(idx & 0x0F) << 12
        case .raw(let v): return v & 0xFFFF_FFF0
        }
    }

    /// Entry as stored in the matrix: action | slot (1…10) in the low nibble (KeyCodeHasIndex=1).
    public static func entry(_ a: ButtonAction, slot: Int) -> UInt32 { (encode(a) & 0xFFFF_FFF0) | UInt32(slot & 0x0F) }

    public static func decode(_ entry: UInt32) -> ButtonAction {
        let v = entry & 0xFFFF_FFF0
        let b0 = UInt8(v & 0xF0)
        let b1 = UInt8((v >> 8) & 0xFF), b2 = UInt8((v >> 16) & 0xFF), b3 = UInt8((v >> 24) & 0xFF)
        switch b0 {
        case 0x10 where b2 == 0 && b3 == 0 && b1 & 0xF0 == 0xF0:
            if let mb = MouseButton(rawValue: b1 & 0x0F) { return .mouse(mb) }
        case 0x20:
            return v == 0x0232_F020 ? .doubleClick : .fire(key: b1, intervalMs: b2, count: b3)
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
            for mk in MediaKey.allCases where encode(.media(mk)) == v { return .media(mk) }
        case 0x90:
            if let mode = MacroRepeat(rawValue: b1 & 0x0F) { return .macro(index: Int(b1 >> 4), mode: mode) }
        default: break
        }
        return .raw(v)
    }

    /// 128-byte macro buffer (MacProtocol=2).
    public static func encode(_ m: Macro) -> [UInt8] {
        let size = PC205.macroSize
        var out = [UInt8](repeating: 0, count: size)
        let rc = m.repeatCount == 0 ? 1 : m.repeatCount
        out[0] = UInt8(rc >> 8)
        out[1] = UInt8(rc & 0xFF)
        var i = 2
        for e in m.events {
            let delay = max(0, min(PC205.macroMaxDelay, e.delayMs))
            let long = delay > 0x7F
            if i >= (long ? size - 5 : size - 3) { break }
            let flag: UInt8 = e.press ? 0x80 : 0x00
            if long {
                out[i] = flag | UInt8(delay % 100); out[i + 1] = e.key; out[i + 2] = UInt8(delay / 100); out[i + 3] = 0x03
                i += 4
            } else {
                out[i] = flag | UInt8(delay == 0 ? 1 : delay); out[i + 1] = e.key
                i += 2
            }
        }
        return out
    }

    public static func decodeMacro(_ b: [UInt8], name: String) -> Macro {
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

    /// Matrix report (feature 6) payload: 8 macro buffers, then 3 modes × 10 little-endian key entries.
    public static func matrixPayload(_ p: Profile) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: PC205.matrixPayload)
        let used = Set(p.buttons.flatMap { $0 }.compactMap { a -> Int? in
            if case let .macro(i, _) = a { return i } else { return nil }
        })
        for i in used where (1...PC205.macroCount).contains(i) && i <= p.macros.count {
            out.replaceSubrange((i - 1) * PC205.macroSize ..< i * PC205.macroSize, with: encode(p.macros[i - 1]))
        }
        var off = PC205.macroAreaSize
        for m in 0..<PC205.modes {
            for s in 0..<PC205.slots {
                let a = m < p.buttons.count && s < p.buttons[m].count ? p.buttons[m][s] : .disabled
                let v = entry(a, slot: s + 1)
                out[off] = UInt8(v & 0xFF); out[off + 1] = UInt8((v >> 8) & 0xFF)
                out[off + 2] = UInt8((v >> 16) & 0xFF); out[off + 3] = UInt8((v >> 24) & 0xFF)
                off += 4
            }
        }
        return out
    }

    public static func matrixFeature(_ p: Profile) -> [UInt8] { [PC205.matrixReportID] + matrixPayload(p) }

    public static func apply(_ p: Profile, to g: inout GeneralReport, parts: MouseParts) {
        if parts.contains(.dpi) {
            g.xyIndependent = p.xyIndependent
            g.stages = p.stages
            g.currentStage = p.currentStage
        }
        if parts.contains(.lighting) {
            g.effect = p.effect
            g.level = p.level
            g.colors = p.colors
            g.lightingFlags = (p.lightingRandom ? 0x80 : 0) | (g.lightingFlags & 0x78) | UInt8(p.lightingColorCount & 0x07)
        }
    }

    public static func apply(_ p: Profile, to m: inout ModeReport) {
        m.activeMode = p.activeMode
        for i in 0..<PC205.modes { m.setRateHz(i < p.ratesHz.count ? p.ratesHz[i] : 500, mode: i) }
    }

    public static func load(_ p: inout Profile, from g: GeneralReport) {
        p.xyIndependent = g.xyIndependent
        p.stages = g.stages.enumerated().map { i, s in
            var s = s
            if s.x == 0, i < p.stages.count { s.x = p.stages[i].x; s.y = p.stages[i].y }
            return s
        }
        p.currentStage = g.currentStage
        p.effect = g.effect
        p.level = g.level
        p.colors = g.colors
        p.lightingRandom = g.lightingFlags & 0x80 != 0
        p.lightingColorCount = Int(g.lightingFlags & 0x07)
    }

    public static func load(_ p: inout Profile, from m: ModeReport) {
        p.activeMode = m.activeMode
        p.ratesHz = (0..<PC205.modes).map { m.rateHz(mode: $0) }
    }
}

/// General report (feature ID 4), 58-byte payload. Read-modify-write keeps unknown bytes.
public struct GeneralReport: Equatable {
    public var bytes: [UInt8]

    public init(payload: [UInt8]) {
        var b = Array(payload.prefix(PC205.generalPayload))
        if b.count < PC205.generalPayload { b += [UInt8](repeating: 0, count: PC205.generalPayload - b.count) }
        bytes = b
    }
    public init(feature: [UInt8]) { self.init(payload: Array(feature.dropFirst())) }
    public var featureBytes: [UInt8] { [PC205.generalReportID] + bytes }

    public var sensorCode: UInt8 { bytes[0] }
    public var signatureOK: Bool { Array(bytes[52..<58]) == PC205.signature }

    public var currentStage: Int {
        get { Int(bytes[1] >> 4) }
        set { bytes[1] = (bytes[1] & 0x0F) | UInt8((newValue & 0x0F) << 4) }
    }
    public var xyIndependent: Bool {
        get { bytes[2] & 0x0F != 0 }
        set { bytes[2] = (bytes[2] & 0xF0) | (newValue ? 1 : 0) }
    }

    public var stages: [DPIStage] {
        get {
            (0..<PC205.dpiStages).map { i in
                let xb: UInt8, yb: UInt8
                if xyIndependent { xb = bytes[4 + 2 * i]; yb = bytes[5 + 2 * i] } else { xb = bytes[4 + i]; yb = xb }
                return DPIStage(enabled: xb & 0x80 == 0, x: PC205.dpi(forCode: xb) ?? 0,
                                y: PC205.dpi(forCode: yb) ?? 0, color: Int(bytes[43 + i] & 0x07))
            }
        }
        set {
            for i in 4...19 { bytes[i] = 0x80 }
            var enabled = 0
            for (i, s) in newValue.prefix(PC205.dpiStages).enumerated() {
                let flag: UInt8 = s.enabled ? 0 : 0x80
                if xyIndependent {
                    bytes[4 + 2 * i] = (PC205.dpiCode(for: s.x) & 0x7F) | flag
                    bytes[5 + 2 * i] = (PC205.dpiCode(for: s.y) & 0x7F) | flag
                } else {
                    bytes[4 + i] = (PC205.dpiCode(for: s.x) & 0x7F) | flag
                }
                bytes[43 + i] = UInt8(s.color & 0x07)
                if s.enabled { enabled += 1 }
            }
            bytes[1] = (bytes[1] & 0xF0) | UInt8(enabled & 0x0F)
        }
    }

    /// Effect index (11 = off) ⇄ high nibble of byte 20 (index+1, 0 = off).
    public var effect: Int {
        get { bytes[20] >> 4 == 0 ? 11 : Int(bytes[20] >> 4) - 1 }
        set { bytes[20] = (UInt8(newValue >= 11 ? 0 : newValue + 1) << 4) | (bytes[20] & 0x0F) }
    }
    /// Low nibble of byte 20: speed (most effects) or brightness (Steady).
    public var level: Int {
        get { Int(bytes[20] & 0x0F) }
        set { bytes[20] = (bytes[20] & 0xF0) | UInt8(max(0, min(15, newValue))) }
    }
    /// Byte 21: bit7 = random/colourful variant, low bits = colour count.
    public var lightingFlags: UInt8 {
        get { bytes[21] }
        set { bytes[21] = newValue }
    }
    public var colors: [RGB] {
        get { (0..<7).map { RGB(bytes[22 + 3 * $0], bytes[23 + 3 * $0], bytes[24 + 3 * $0]) } }
        set {
            for i in 0..<7 {
                let c = i < newValue.count ? newValue[i] : RGB(0, 0, 0)
                bytes[22 + 3 * i] = c.r; bytes[23 + 3 * i] = c.g; bytes[24 + 3 * i] = c.b
            }
        }
    }
}

/// Mode report (feature ID 8). 8-byte payload: [activeMode+1, rate1, rate2, rate3, ...preserved].
public struct ModeReport: Equatable {
    public var bytes: [UInt8]
    public init(payload: [UInt8]) {
        var b = Array(payload.prefix(PC205.modePayload))
        if b.count < PC205.modePayload { b += [UInt8](repeating: 0, count: PC205.modePayload - b.count) }
        bytes = b
    }
    public init(feature: [UInt8]) { self.init(payload: Array(feature.dropFirst())) }
    public var featureBytes: [UInt8] { [PC205.modeReportID] + bytes }

    public var activeMode: Int {
        get { max(0, Int(bytes[0]) - 1) }
        set { bytes[0] = UInt8(max(0, min(PC205.modes - 1, newValue)) + 1) }
    }
    public func rateHz(mode: Int) -> Int {
        let c = Int(bytes[1 + mode])
        return (1...4).contains(c) ? PC205.pollingHz[c - 1] : 500
    }
    public mutating func setRateHz(_ hz: Int, mode: Int) {
        bytes[1 + mode] = UInt8((PC205.pollingHz.firstIndex(of: hz) ?? 2) + 1)
    }
}
