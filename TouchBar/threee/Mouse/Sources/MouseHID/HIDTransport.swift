import Foundation
import IOKit
import IOKit.hid
import MouseCore

public enum HIDError: Error, CustomStringConvertible {
    case notFound
    case openFailed(IOReturn)
    case ioFailed(String, IOReturn)

    public var description: String {
        switch self {
        case .notFound: return "mouse configuration interface not found"
        case .openFailed(let r): return String(format: "IOHIDDeviceOpen failed: 0x%08x", r)
        case .ioFailed(let what, let r): return String(format: "%@ failed: 0x%08x", what, r)
        }
    }
}

/// One HID device/collection of a mouse.
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

/// Thin IOKit HID wrapper for one VID/PID, used by device drivers. Never seizes the device,
/// so the mouse keeps working while it is configured.
public final class HIDTransport {
    private let manager: IOHIDManager
    public private(set) var interfaces: [HIDInterfaceInfo] = []
    private var opened = Set<ObjectIdentifier>()

    public init(vendorID: Int, productID: Int) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        for i in interfaces where opened.contains(ObjectIdentifier(i.device)) {
            IOHIDDeviceClose(i.device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    static func intProp(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    /// VID/PID pairs of every HID device currently attached (for MouseDevices.detect()).
    public static func presentDevices() -> Set<[Int]> {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, nil)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { return [] }
        return Set(set.map { [intProp($0, kIOHIDVendorIDKey), intProp($0, kIOHIDProductIDKey)] })
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

    private func ensureOpen(_ d: IOHIDDevice) throws {
        let id = ObjectIdentifier(d)
        if opened.contains(id) { return }
        let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw HIDError.openFailed(r) }
        opened.insert(id)
    }

    /// `bytes[0]` must be the report ID.
    public func setFeature(_ bytes: [UInt8], on iface: HIDInterfaceInfo) throws {
        try ensureOpen(iface.device)
        let reportID = CFIndex(bytes[0])
        var result = kIOReturnError
        for attempt in 0..<3 {
            result = bytes.withUnsafeBufferPointer { p in
                IOHIDDeviceSetReport(iface.device, kIOHIDReportTypeFeature, reportID, p.baseAddress!, p.count)
            }
            if result == kIOReturnSuccess { return }
            if attempt < 2 { usleep(200_000) }
        }
        throw HIDError.ioFailed("SetFeature(0x\(String(reportID, radix: 16)))", result)
    }

    /// Returns `length` bytes including the leading report ID byte.
    public func getFeature(reportID: UInt8, length: Int, on iface: HIDInterfaceInfo) throws -> [UInt8] {
        try ensureOpen(iface.device)
        var buf = [UInt8](repeating: 0, count: length)
        buf[0] = reportID
        var len = CFIndex(length)
        let r = buf.withUnsafeMutableBufferPointer { p in
            IOHIDDeviceGetReport(iface.device, kIOHIDReportTypeFeature, CFIndex(reportID), p.baseAddress!, &len)
        }
        guard r == kIOReturnSuccess else { throw HIDError.ioFailed("GetFeature(0x\(String(reportID, radix: 16)))", r) }
        // macOS may or may not keep the report ID in the buffer; normalise so index 0 is the ID.
        var out = Array(buf.prefix(Int(len)))
        if out.first != reportID { out.insert(reportID, at: 0) }
        if out.count < length { out += [UInt8](repeating: 0, count: length - out.count) }
        return Array(out.prefix(length))
    }
}

/// Registry of supported mice.
public enum MouseDevices {
    /// Every supported mouse. Adding a mouse = adding its Devices/<Name> code and one line here.
    public static let supported: [MouseDeviceEntry] = [
        PC205Driver.entry,
    ]

    /// Supported mice that are plugged in now.
    public static func detect() -> [MouseDeviceEntry] {
        let present = HIDTransport.presentDevices()
        return supported.filter { present.contains([$0.vendorID, $0.productID]) }
    }
}
