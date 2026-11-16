import Foundation
import MouseCore

/// PC205 driver: picks the HID collection for each feature report and sends the same
/// read-modify-write sequence as the vendor's Apply_M_AJ_8832_3 (Shared/PC205/PROTOCOL.md).
public final class PC205Driver: MouseDriver {
    public static let entry = MouseDeviceEntry(id: PC205.id, name: PC205.name,
                                               vendorID: PC205.vendorID, productID: PC205.productID) { PC205Driver() }

    let transport = HIDTransport(vendorID: PC205.vendorID, productID: PC205.productID)
    var general: HIDInterfaceInfo?
    var matrix: HIDInterfaceInfo?
    var mode: HIDInterfaceInfo?
    var lastGeneral: GeneralReport?

    public init() {}
    public var id: String { PC205.id }
    public var displayName: String { PC205.name }
    public var capabilities: MouseCapabilities { PC205.capabilities }
    public func defaultProfile() -> Profile { PC205.defaultProfile() }
    public var log: (String) -> Void = { print($0) }
    public var isReady: Bool { general != nil && matrix != nil }

    @discardableResult
    public func connect() -> Bool {
        let ifs = transport.refresh()
        general = nil; matrix = nil; mode = nil
        for i in ifs { log("found \(i)") }
        let ordered = ifs.sorted { a, b in
            (a.usagePage == PC205.vendorUsagePage ? 0 : 1) < (b.usagePage == PC205.vendorUsagePage ? 0 : 1)
        }
        // General: must answer GetFeature(4); prefer the one carrying the "FR2763" signature.
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
        return isReady
    }

    func readGeneral() throws -> GeneralReport {
        guard let g = general else { throw HIDError.notFound }
        return GeneralReport(feature: try transport.getFeature(reportID: PC205.generalReportID, length: PC205.generalPayload + 1, on: g))
    }

    func readMode() throws -> ModeReport? {
        guard let m = mode else { return nil }
        return ModeReport(feature: try transport.getFeature(reportID: PC205.modeReportID, length: PC205.modePayload + 1, on: m))
    }

    public func read(into profile: inout Profile) throws -> String {
        let g = try readGeneral()
        lastGeneral = g
        PC205Codec.load(&profile, from: g)
        if let m = try readMode() { PC205Codec.load(&profile, from: m) }
        // The vendor app never reads the matrix back either; buttons/macros come from the saved profile.
        return "sensor \(PC205.sensorNames[g.sensorCode] ?? String(g.sensorCode)), signature \(g.signatureOK ? "OK" : "unexpected")"
    }

    /// Vendor order: GetFeature(4) → SetFeature(4) → mode (8) → SetFeature(6), 20 ms apart.
    public func apply(_ p: Profile, parts: MouseParts) throws {
        guard let gi = general, let mi = matrix else { throw HIDError.notFound }
        if !parts.isDisjoint(with: [.dpi, .lighting]) {
            var g = try readGeneral()
            if !g.signatureOK { log("warning: general report signature is not FR2763 – writing anyway") }
            PC205Codec.apply(p, to: &g, parts: parts)
            usleep(20_000)
            try transport.setFeature(g.featureBytes, on: gi)
            lastGeneral = g
            log("SetFeature(4) ok")
        }
        if parts.contains(.polling), let modeIf = mode {
            usleep(20_000)
            if var m = try readMode() {
                PC205Codec.apply(p, to: &m)
                usleep(20_000)
                try transport.setFeature(m.featureBytes, on: modeIf)
                log("SetFeature(8) ok")
            }
        }
        if parts.contains(.buttons) {
            usleep(20_000)
            try transport.setFeature(PC205Codec.matrixFeature(p), on: mi)
            log("SetFeature(6) ok")
        }
    }

    public func diagnostics() -> [String] {
        var lines = transport.interfaces.map { "\($0)" }
        if isReady && mode == nil { lines.append("Mode / polling-rate collection (feature 8) not found: polling rate can't be applied.") }
        if let g = lastGeneral { lines.append("General report (ID 4): " + g.featureBytes.map { String(format: "%02X", $0) }.joined(separator: " ")) }
        return lines
    }
}
