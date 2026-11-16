// swift-tools-version:5.9
// 3£ Mouse: gaming-mouse settings opened from the 3£ menu ("Mouse…").
// Built by TouchBar/threee/Mouse/build-helper.sh into 3E.app/Contents/Helpers/3£ Mouse.app.
//
// Layout (same split as Windows/Mouse):
//   MouseCore            device-independent model, capabilities, MouseDriver protocol
//   MouseCore/Devices/X  pure protocol code for mouse X (testable, no IOKit)
//   MouseHID             IOKit HID transport + registry of supported mice
//   MouseHID/Devices/X   driver for mouse X (matched by VID/PID)
//   ThreeEMouse          SwiftUI window built from MouseCapabilities
// Adding a mouse = one Devices/<Name> folder in each target + one registry line.
import PackageDescription

let package = Package(
    name: "ThreeEMouse",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ThreeEMouse", targets: ["ThreeEMouse"]),
        .executable(name: "mousectl", targets: ["mousectl"]),
    ],
    targets: [
        .target(name: "MouseCore"),
        .target(name: "MouseHID", dependencies: ["MouseCore"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "ThreeEMouse", dependencies: ["MouseCore", "MouseHID"]),
        .executableTarget(name: "mousectl", dependencies: ["MouseCore", "MouseHID"]),
        .testTarget(name: "MouseCoreTests", dependencies: ["MouseCore"]),
    ]
)
