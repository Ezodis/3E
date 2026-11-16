import Foundation
import IOKit
import IOKit.hid
import PC205Core

public enum HIDError: Error, CustomStringConvertible {
    case notFound
    case openFailed(IOReturn)
    case ioFailed(String, IOReturn)
    case shortRead(Int)

    public var description: String {
        switch self {
        case .notFound: return "PC205 (VID 0x258A / PID 0x1007) not found"
        case .openFailed(let r): return String(format: "IOHIDDeviceOpen failed: 0x%08x", r)
        case .ioFailed(let what, let r): return String(format: "%@ failed: 0x%08x", what, r)
        case .shortRead(let n): return "short feature read (\(n) bytes)"
        }
    }
}

/// One HID top-level collection of the mouse (macOS exposes each collection as its own IOHIDDevice).
public struct HIDInterfaceInfo: CustomStringConvertible {
    public let device: IOHIDDevice
    public let usagePage: Int
    public let usage: Int
    public let maxFeature: Int
    public let maxOutput: Int
    public let maxInput: Int
    public let product: String
    public var description: String {
        String(format: "UsagePage=0x%04x Usage=0x%04x feature=%d output=%d input=%d \"%@\"",
               usagePage, usage, maxFeature, maxOutput, maxInput, product)
    }
}

/// Thin IOKit HID wrapper. Only feature reports are used, exactly like the vendor's
/// Lowerdev.dll (HidD_SetFeature / HidD_GetFeature).
public final class HIDTransport {
    private let manager: IOHIDManager
    public private(set) var interfaces: [HIDInterfaceInfo] = []
    private var opened = Set<ObjectIdentifier>()

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: PC205.vendorID, kIOHIDProductIDKey: PC205.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        for i in interfaces where opened.contains(ObjectIdentifier(i.device)) {
            IOHIDDeviceClose(i.device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private static func intProp(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    @discardableResult
    public func refresh() -> [HIDInterfaceInfo] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            interfaces = []
            return []
        }
        interfaces = set.map { d in
            HIDInterfaceInfo(
                device: d,
                usagePage: Self.intProp(d, kIOHIDPrimaryUsagePageKey),
                usage: Self.intProp(d, kIOHIDPrimaryUsageKey),
                maxFeature: Self.intProp(d, kIOHIDMaxFeatureReportSizeKey),
                maxOutput: Self.intProp(d, kIOHIDMaxOutputReportSizeKey),
                maxInput: Self.intProp(d, kIOHIDMaxInputReportSizeKey),
                product: (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "")
        }.sorted { ($0.usagePage, $0.usage) < ($1.usagePage, $1.usage) }
        return interfaces
    }

    public var isConnected: Bool { !interfaces.isEmpty }

    /// Finds the collection that declares the given feature report ID with (at least) the given length.
    /// Falls back to the vendor-defined page / largest feature size, which is how the Windows
    /// driver picks its handles (it matches on FeatureReportByteLength).
    public func interface(forFeatureLength len: Int) -> HIDInterfaceInfo? {
        if let exact = interfaces.first(where: { $0.maxFeature == len }) { return exact }
        return interfaces.filter { $0.maxFeature >= len }.min { $0.maxFeature < $1.maxFeature }
    }

    private func ensureOpen(_ d: IOHIDDevice) throws {
        let id = ObjectIdentifier(d)
        if opened.contains(id) { return }
        // Seize is never used: the mouse keeps working normally while we configure it.
        let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw HIDError.openFailed(r) }
        opened.insert(id)
    }

    /// `bytes[0]` must be the report ID (Windows HidD_SetFeature convention).
    public func setFeature(_ bytes: [UInt8], on iface: HIDInterfaceInfo) throws {
        try ensureOpen(iface.device)
        let reportID = CFIndex(bytes[0])
        let r = bytes.withUnsafeBufferPointer { p in
            IOHIDDeviceSetReport(iface.device, kIOHIDReportTypeFeature, reportID, p.baseAddress!, p.count)
        }
        guard r == kIOReturnSuccess else { throw HIDError.ioFailed("SetFeature(0x\(String(reportID, radix: 16)))", r) }
    }

    /// Returns the report including the leading report ID byte.
    public func getFeature(reportID: UInt8, length: Int, on iface: HIDInterfaceInfo) throws -> [UInt8] {
        try ensureOpen(iface.device)
        var buf = [UInt8](repeating: 0, count: length)
        buf[0] = reportID
        var len = CFIndex(length)
        let r = buf.withUnsafeMutableBufferPointer { p in
            IOHIDDeviceGetReport(iface.device, kIOHIDReportTypeFeature, CFIndex(reportID), p.baseAddress!, &len)
        }
        guard r == kIOReturnSuccess else { throw HIDError.ioFailed("GetFeature(0x\(String(reportID, radix: 16)))", r) }
        // macOS may or may not keep the report ID in the buffer depending on the driver;
        // normalise so index 0 is always the report ID.
        var out = Array(buf.prefix(Int(len)))
        if out.first != reportID { out.insert(reportID, at: 0) }
        if out.count < length { out += [UInt8](repeating: 0, count: length - out.count) }
        return Array(out.prefix(length))
    }
}
