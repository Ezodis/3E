import Foundation
import MouseCore
import MouseHID

// mousectl – command-line companion to 3£ Mouse. Works with any supported mouse.
// Uses the profile the app saved (~/Library/Application Support/3E Mouse/<device>.json) when present,
// so changing one button does not wipe the others.

let usage = """
usage: mousectl <command>
  list                       supported mice, which are plugged in, and their HID interfaces
  dump                       what the connected mouse reports
  side <key> [slot]          map the extra side button (or a slot) to a key in every mode, e.g. F13 or Pause
  button <mode> <slot> <key> map one slot in one mode (1-based) to a key
  rate <hz>                  set the polling rate for every mode
  apply                      write the saved profile
  defaults                   write the device's default profile
"""

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(0) }

if cmd == "list" {
    for e in MouseDevices.supported { print(String(format: "supported: %@ (%04X:%04X)", e.name, e.vendorID, e.productID)) }
}
guard let entry = MouseDevices.detect().first else {
    if cmd == "list" { print("no supported mouse plugged in"); exit(0) }
    die("No supported mouse plugged in.")
}
let driver = entry.make()
driver.log = { FileHandle.standardError.write(("  " + $0 + "\n").data(using: .utf8)!) }
let ready = driver.connect()
let caps = driver.capabilities
if cmd != "list" && !ready { die("\(driver.displayName): configuration interface not found (try `mousectl list`).") }

let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("3E Mouse/\(driver.id).json")

func loadProfile() -> Profile {
    let defaults = driver.defaultProfile()
    if let d = try? Data(contentsOf: storeURL), let p = try? JSONDecoder().decode(Profile.self, from: d) {
        return p.normalized(caps, defaults: defaults)
    }
    return defaults.normalized(caps, defaults: defaults)
}

func saveProfile(_ p: Profile) {
    try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let d = try? JSONEncoder().encode(p) { try? d.write(to: storeURL) }
}

do {
    switch cmd {
    case "list":
        print("connected: \(driver.displayName)")
        for line in driver.diagnostics() { print("  " + line) }
    case "dump":
        var p = loadProfile()
        print(try driver.read(into: &p))
        for line in driver.diagnostics() { print(line) }
        for (i, s) in p.stages.enumerated() { print("stage \(i + 1): \(s.enabled ? "on " : "off") \(s.x)x\(s.y)") }
        if caps.hasPolling { print("polling:", p.ratesHz.map { "\($0) Hz" }.joined(separator: ", ")) }
    case "side", "button":
        guard caps.hasButtons else { die("\(driver.displayName) has no remappable buttons.") }
        var p = loadProfile()
        let keyName: String, slot: Int, modes: [Int]
        if cmd == "side" {
            guard args.count >= 2 else { die(usage) }
            keyName = args[1]; slot = args.count > 2 ? Int(args[2]) ?? 0 : caps.extraSideSlot
            modes = Array(p.buttons.indices)
        } else {
            guard args.count >= 4, let m = Int(args[1]), let s = Int(args[2]), (1...p.buttons.count).contains(m) else { die(usage) }
            keyName = args[3]; slot = s; modes = [m - 1]
        }
        guard (1...caps.slots).contains(slot) else { die("slot must be 1…\(caps.slots)") }
        guard let k = HIDKey.usage(named: keyName) else { die("unknown key \(keyName)") }
        for m in modes { p.buttons[m][slot - 1] = .keyPress(k) }
        try driver.apply(p, parts: .buttons)
        saveProfile(p)
        print("\(caps.slotName(slot)) → \(HIDKey.name(k))")
    case "rate":
        guard caps.hasPolling, args.count >= 2, let hz = Int(args[1]), caps.pollingRatesHz.contains(hz) else {
            die("rates: " + caps.pollingRatesHz.map(String.init).joined(separator: ", "))
        }
        var p = loadProfile()
        p.ratesHz = Array(repeating: hz, count: max(1, caps.modes))
        try driver.apply(p, parts: .polling)
        saveProfile(p)
        print("polling rate \(hz) Hz")
    case "apply":
        try driver.apply(loadProfile(), parts: .all)
        print("applied saved profile")
    case "defaults":
        let p = driver.defaultProfile().normalized(caps, defaults: driver.defaultProfile())
        try driver.apply(p, parts: .all)
        saveProfile(p)
        print("applied defaults")
    default:
        print(usage)
    }
} catch {
    die("error: \(error)")
}
