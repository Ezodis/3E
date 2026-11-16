import Foundation
import PC205Core

/// High-level access to the mouse: picks the right HID collection for each report and
/// performs the same read-modify-write sequence as the vendor's Apply_M_AJ_8832_3.
public final class PC205Device {
    public let transport = HIDTransport()
    public private(set) var general: HIDInterfaceInfo?
    public private(set) var matrix: HIDInterfaceInfo?
    public private(set) var mode: HIDInterfaceInfo?
    public var log: (String) -> Void = { print($0) }

    public init() {}

    /// Re-enumerates and selects interfaces. Returns true when the general + matrix collections are found.
    @discardableResult
    public func connect() -> Bool {
        let ifs = transport.refresh()
        general = nil; matrix = nil; mode = nil
        guard !ifs.isEmpty else { return false }
        for i in ifs { log("found \(i)") }
        // Prefer vendor-page collections, then anything with a big enough feature report.
        let ordered = ifs.sorted { a, b in
            (a.usagePage == PC205.vendorUsagePage ? 0 : 1) < (b.usagePage == PC205.vendorUsagePage ? 0 : 1)
        }
        // General: must answer GetFeature(4) – prefer one whose payload carries the "FR2763" signature.
        var fallback: HIDInterfaceInfo?
        for i in ordered where i.maxFeature >= PC205.generalPayload + 1 {
            if let f = try? transport.getFeature(reportID: PC205.generalReportID, length: PC205.generalPayload + 1, on: i) {
                if GeneralReport(feature: f).signatureOK { general = i; break }
                if fallback == nil { fallback = i }
            }
        }
        if general == nil { general = fallback }
        matrix = ordered.first { $0.maxFeature >= PC205.matrixPayload + 1 }
        for i in ordered where i.maxFeature >= PC205.modePayload + 1 {
            if (try? transport.getFeature(reportID: PC205.modeReportID, length: PC205.modePayload + 1, on: i)) != nil {
                mode = i; break
            }
        }
        log("general: \(general.map { "\($0)" } ?? "none")")
        log("matrix:  \(matrix.map { "\($0)" } ?? "none")")
        log("mode:    \(mode.map { "\($0)" } ?? "none")")
        return general != nil && matrix != nil
    }

    public var isReady: Bool { general != nil && matrix != nil }

    public func readGeneral() throws -> GeneralReport {
        guard let g = general else { throw HIDError.notFound }
        return GeneralReport(feature: try transport.getFeature(reportID: PC205.generalReportID,
                                                               length: PC205.generalPayload + 1, on: g))
    }

    public func readMode() throws -> ModeReport? {
        guard let m = mode else { return nil }
        return ModeReport(feature: try transport.getFeature(reportID: PC205.modeReportID,
                                                            length: PC205.modePayload + 1, on: m))
    }

    /// The vendor app never reads the matrix back; try anyway (some firmwares answer).
    public func readMatrix() -> [UInt8]? {
        guard let m = matrix,
              let f = try? transport.getFeature(reportID: PC205.matrixReportID, length: PC205.matrixPayload + 1, on: m)
        else { return nil }
        let p = Array(f.dropFirst())
        // All-zero or all-0xFF means "not supported".
        if p.allSatisfy({ $0 == 0 }) || p.allSatisfy({ $0 == 0xFF }) { return nil }
        return p
    }

    public struct ApplyParts: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let general = ApplyParts(rawValue: 1)   // DPI + lighting
        public static let mode = ApplyParts(rawValue: 2)      // polling rate + active mode
        public static let matrix = ApplyParts(rawValue: 4)    // buttons + macros
        public static let all: ApplyParts = [.general, .mode, .matrix]
    }

    /// Same order as the vendor: GetFeature(4) → SetFeature(4) → mode (8) → SetFeature(6), 20 ms apart.
    public func apply(_ p: Profile, parts: ApplyParts = .all) throws {
        guard let gi = general, let mi = matrix else { throw HIDError.notFound }
        if parts.contains(.general) {
            var g = try readGeneral()
            if !g.signatureOK { log("warning: general report signature is not FR2763 – writing anyway") }
            p.apply(to: &g)
            usleep(20_000)
            try transport.setFeature(g.featureBytes, on: gi)
            log("SetFeature(4) ok")
        }
        if parts.contains(.mode), let modeIf = mode {
            usleep(20_000)
            if var m = try readMode() {
                p.apply(to: &m)
                usleep(20_000)
                try transport.setFeature(m.featureBytes, on: modeIf)
                log("SetFeature(8) ok")
            }
        }
        if parts.contains(.matrix) {
            usleep(20_000)
            try transport.setFeature(p.matrixFeature(), on: mi)
            log("SetFeature(6) ok")
        }
    }
}
