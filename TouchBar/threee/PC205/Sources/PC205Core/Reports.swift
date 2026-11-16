import Foundation

/// General report (feature ID 4). Wraps the 58-byte payload (without report ID) so that bytes we do not
/// understand are preserved exactly (read-modify-write, like the vendor app).
public struct GeneralReport: Equatable {
    public var bytes: [UInt8]

    public init(payload: [UInt8]) {
        var b = Array(payload.prefix(PC205.generalPayload))
        if b.count < PC205.generalPayload { b += [UInt8](repeating: 0, count: PC205.generalPayload - b.count) }
        bytes = b
    }

    /// Builds the report from a feature buffer that starts with the report ID.
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

    /// Per-stage DPI (X, Y). Y == X unless xyIndependent.
    public struct Stage: Equatable, Codable {
        public var enabled: Bool
        public var x: Int
        public var y: Int
        public var color: DPIColor
        public init(enabled: Bool, x: Int, y: Int? = nil, color: DPIColor) {
            self.enabled = enabled; self.x = x; self.y = y ?? x; self.color = color
        }
    }

    public var stages: [Stage] {
        get {
            (0..<PC205.dpiStages).map { i in
                let xb: UInt8, yb: UInt8
                if xyIndependent { xb = bytes[4 + 2 * i]; yb = bytes[5 + 2 * i] } else { xb = bytes[4 + i]; yb = xb }
                return Stage(enabled: xb & 0x80 == 0,
                             x: PC205.dpi(forCode: xb) ?? 0,
                             y: PC205.dpi(forCode: yb) ?? 0,
                             color: DPIColor(rawValue: bytes[43 + i] & 0x07) ?? .none)
            }
        }
        set {
            precondition(newValue.count == PC205.dpiStages)
            for i in 4...19 { bytes[i] = 0x80 }
            var enabled = 0
            for (i, s) in newValue.enumerated() {
                let flag: UInt8 = s.enabled ? 0 : 0x80
                if xyIndependent {
                    bytes[4 + 2 * i] = (PC205.dpiCode(for: s.x) & 0x7F) | flag
                    bytes[5 + 2 * i] = (PC205.dpiCode(for: s.y) & 0x7F) | flag
                } else {
                    bytes[4 + i] = (PC205.dpiCode(for: s.x) & 0x7F) | flag
                }
                bytes[43 + i] = s.color.rawValue
                if s.enabled { enabled += 1 }
            }
            bytes[1] = (bytes[1] & 0xF0) | UInt8(enabled & 0x0F)
        }
    }

    public var effect: LightingEffect {
        get { LightingEffect(hardware: bytes[20] >> 4) }
        set { bytes[20] = (newValue.hardwareValue << 4) | (bytes[20] & 0x0F) }
    }

    /// Low nibble of byte 20: speed (most effects) or brightness level (Steady), 1…8 in the vendor UI.
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

    /// 0-based active key mode.
    public var activeMode: Int {
        get { max(0, Int(bytes[0]) - 1) }
        set { bytes[0] = UInt8(max(0, min(PC205.modes - 1, newValue)) + 1) }
    }
    public func rate(mode: Int) -> PollingRate { PollingRate(rawValue: bytes[1 + mode]) ?? .hz500 }
    public mutating func setRate(_ r: PollingRate, mode: Int) { bytes[1 + mode] = r.rawValue }
}
