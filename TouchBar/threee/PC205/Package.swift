// swift-tools-version:5.9
// 3£ Mouse: configurator for the Thunderbird PC205 (Sinowealth 258A:1007).
// Built by TouchBar/threee/PC205/build-helper.sh into 3E.app/Contents/Helpers/3£ Mouse.app.
// Protocol: Shared/PC205/PROTOCOL.md (shared with the Windows 3£ Mouse window).
import PackageDescription

let package = Package(
    name: "ThreeEMouse",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ThreeEMouse", targets: ["ThreeEMouse"]),
        .executable(name: "pc205ctl", targets: ["pc205ctl"]),
    ],
    targets: [
        // Pure protocol encoding/decoding. No IOKit, so it is unit-testable anywhere.
        .target(name: "PC205Core"),
        // IOKit HID transport (macOS only).
        .target(name: "PC205HID", dependencies: ["PC205Core"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        // SwiftUI window opened from the 3£ menu ("Mouse (PC205)…").
        .executableTarget(name: "ThreeEMouse", dependencies: ["PC205Core", "PC205HID"]),
        // Command-line tool for dumping / scripting.
        .executableTarget(name: "pc205ctl", dependencies: ["PC205Core", "PC205HID"]),
        .testTarget(name: "PC205CoreTests", dependencies: ["PC205Core"]),
    ]
)
