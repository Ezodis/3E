import Foundation
import PC205Core
import PC205HID

// pc205ctl – command-line companion to 3£ Mouse.
// Uses the profile the app saved (~/Library/Application Support/3E Mouse/profile.json) when present,
// so changing one button does not wipe the others (the matrix report is always written as a whole).

let usage = """
usage: pc205ctl <command>
  list                       list the mouse's HID collections and which one is used for what
  dump                       print general (4) and mode (8) feature reports
  side <key> [slot]          map the extra side button (default slot \(Profile.likelyExtraSideSlot)) to a key, e.g. F13 or Pause
  button <mode> <slot> <key> map one slot in one mode (1-based) to a key
  rate <125|250|500|1000>    set polling rate for all modes
  apply                      write the saved profile (buttons, macros, DPI, lighting, rate)
  defaults                   write the vendor default profile
"""

let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("3E Mouse/profile.json")

func loadProfile() -> Profile {
    if let d = try? Data(contentsOf: storeURL), let p = try? JSONDecoder().decode(Profile.self, from: d) { return p }
    return .vendorDefault
}

func saveProfile(_ p: Profile) {
    try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let d = try? JSONEncoder().encode(p) { try? d.write(to: storeURL) }
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(0) }

let dev = PC205Device()
dev.log = { FileHandle.standardError.write(("  " + $0 + "\n").data(using: .utf8)!) }
let ready = dev.connect()
if cmd != "list" && !ready { die("PC205 configuration interface not found (try `pc205ctl list`).") }

do {
    switch cmd {
    case "list":
        for i in dev.transport.interfaces { print(i) }
        if dev.transport.interfaces.isEmpty { print("no PC205 (258A:1007) HID interfaces found") }
    case "dump":
        let g = try dev.readGeneral()
        print("general:", hex(g.featureBytes))
        print("  sensor:", PC205.sensorNames[g.sensorCode] ?? "\(g.sensorCode)", " signature:", g.signatureOK ? "FR2763 OK" : "unexpected")
        for (i, s) in g.stages.enumerated() { print("  stage \(i + 1): \(s.enabled ? "on " : "off") \(s.x)x\(s.y) \(s.color.name)") }
        print("  effect:", g.effect.name, "level", g.level)
        if let m = try dev.readMode() {
            print("mode:   ", hex(m.featureBytes))
            print("  active mode \(m.activeMode + 1); rates", (0..<3).map { "\(m.rate(mode: $0).hz) Hz" })
        }
        if let x = dev.readMatrix() { print("matrix (read back):", hex(Array(x[0x400..<0x478]))) }
    case "side", "button":
        var p = loadProfile()
        let keyName: String, slot: Int, modes: [Int]
        if cmd == "side" {
            guard args.count >= 2 else { die(usage) }
            keyName = args[1]; slot = args.count > 2 ? Int(args[2]) ?? 0 : Profile.likelyExtraSideSlot
            modes = Array(0..<PC205.modes)
        } else {
            guard args.count >= 4, let m = Int(args[1]), let s = Int(args[2]) else { die(usage) }
            keyName = args[3]; slot = s; modes = [m - 1]
        }
        guard (1...PC205.slots).contains(slot) else { die("slot must be 1…10") }
        guard let k = HIDKey.usage(named: keyName) else { die("unknown key \(keyName)") }
        for m in modes { p.buttons[m][slot - 1] = .keyPress(k) }
        try dev.apply(p, parts: .matrix)
        saveProfile(p)
        print("slot \(slot) → \(HIDKey.name(k)) (entry 0x\(String(ButtonAction.keyPress(k).entry(slot: slot), radix: 16)))")
    case "rate":
        guard args.count >= 2, let hz = Int(args[1]), let r = PollingRate.allCases.first(where: { $0.hz == hz }) else { die(usage) }
        var p = loadProfile()
        p.rates = Array(repeating: r, count: PC205.modes)
        try dev.apply(p, parts: .mode)
        saveProfile(p)
        print("polling rate \(hz) Hz")
    case "apply":
        try dev.apply(loadProfile())
        print("applied saved profile")
    case "defaults":
        try dev.apply(.vendorDefault)
        saveProfile(.vendorDefault)
        print("applied vendor defaults")
    default:
        print(usage)
    }
} catch {
    die("error: \(error)")
}
