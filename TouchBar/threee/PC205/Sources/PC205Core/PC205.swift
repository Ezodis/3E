import Foundation

/// Constants for the Thunderbird PC205 (Sinowealth "8832" firmware, MsFw=7). See PC205/PROTOCOL.md.
public enum PC205 {
    public static let vendorID = 0x258A
    public static let productID = 0x1007
    public static let vendorUsagePage = 0xFF00
    public static let vendorUsage = 0x01

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
    public static let macroAreaSize = macroCount * macroSize   // 0x400

    /// DPISET from Cfg.ini; hardware code = index + 1.
    public static let dpiTable: [Int] = [500, 800, 1000, 1200, 1600, 2000, 2400, 3000,
                                         3200, 3500, 4000, 4500, 5000, 5500, 6000, 7200]
    public static func dpiCode(for dpi: Int) -> UInt8 {
        let i = dpiTable.enumerated().min { abs($0.element - dpi) < abs($1.element - dpi) }!.offset
        return UInt8(i + 1)
    }
    public static func dpi(forCode code: UInt8) -> Int? {
        let i = Int(code & 0x7F) - 1
        return dpiTable.indices.contains(i) ? dpiTable[i] : nil
    }

    /// Device signature from Cfg.ini PSD (= "FR2763").
    public static let signature: [UInt8] = [0x46, 0x52, 0x32, 0x37, 0x36, 0x33]

    public static let sensorNames: [UInt8: String] = [
        1: "0x5050", 2: "0x3050", 3: "0x9800", 4: "0x3320", 5: "0x3330", 6: "0x3360",
        7: "0x3610", 8: "PMW3212 (0x3212)", 9: "0x3310", 11: "0x3325", 12: "0x7350", 14: "0x3327",
    ]
}

/// DPI stage colour palette index used by bytes 43…50 of the general report.
public enum DPIColor: UInt8, CaseIterable, Codable, Identifiable {
    case none = 0, red = 1, green = 2, blue = 3, cyan = 4, yellow = 5, magenta = 6, white = 7
    public var id: UInt8 { rawValue }
    public var name: String { String(describing: self).capitalized }
    public var rgb: RGB {
        switch self {
        case .none: return RGB(0, 0, 0)
        case .red: return RGB(255, 0, 0)
        case .green: return RGB(0, 255, 0)
        case .blue: return RGB(0, 0, 255)
        case .cyan: return RGB(0, 255, 255)
        case .yellow: return RGB(255, 255, 0)
        case .magenta: return RGB(255, 0, 255)
        case .white: return RGB(255, 255, 255)
        }
    }
}

public struct RGB: Codable, Equatable, Hashable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

public enum LightingEffect: Int, CaseIterable, Codable, Identifiable {
    case colorfulStreaming = 0, steady, breathing, tail, neon, colorfulSteady, flicker,
         response, streaming, wave, trailing, off
    public var id: Int { rawValue }
    public var name: String {
        ["Colorful Streaming", "Steady", "Breathing", "Tail", "Neon", "Colorful Steady", "Flicker",
         "Response", "Streaming", "Wave", "Trailing", "Off (None)"][rawValue]
    }
    /// Effects hidden by the vendor UI (LedMask=0x560). Still selectable, flagged in the UI.
    public var hiddenByVendor: Bool { [5, 6, 8, 10].contains(rawValue) }
    var hardwareValue: UInt8 { self == .off ? 0 : UInt8(rawValue + 1) }
    init(hardware: UInt8) { self = hardware == 0 ? .off : (LightingEffect(rawValue: Int(hardware) - 1) ?? .off) }
}

public enum PollingRate: UInt8, CaseIterable, Codable, Identifiable {
    case hz125 = 1, hz250 = 2, hz500 = 3, hz1000 = 4
    public var id: UInt8 { rawValue }
    public var hz: Int { [125, 250, 500, 1000][Int(rawValue) - 1] }
}
