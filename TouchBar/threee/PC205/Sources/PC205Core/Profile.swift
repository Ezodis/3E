import Foundation

/// Everything the vendor app lets you configure, as one Codable value.
public struct Profile: Codable, Equatable {
    public var name: String
    /// [mode][slot] with slot 0…9 meaning hardware slot 1…10.
    public var buttons: [[ButtonAction]]
    public var macros: [Macro]
    public var stages: [GeneralReport.Stage]
    public var currentStage: Int
    public var xyIndependent: Bool
    public var effect: LightingEffect
    public var level: Int
    public var lightingFlags: UInt8
    public var colors: [RGB]
    public var activeMode: Int
    public var rates: [PollingRate]

    /// Hardware slot the user's extra side button most likely is (see PROTOCOL.md §5). Confirm with "Identify buttons".
    public static let likelyExtraSideSlot = 8

    public static let slotNames: [String] = [
        "Slot 1 – Left", "Slot 2 – Right", "Slot 3 – Middle (wheel)", "Slot 4 – Back (MB4)",
        "Slot 5 – Forward (MB5)", "Slot 6 – DPI +", "Slot 7 – DPI −",
        "Slot 8 – Extra side button?", "Slot 9", "Slot 10",
    ]

    /// Vendor defaults from Cfg.ini ([SENSOR_1] K1…K10, DPI, DC, DR).
    public static var vendorDefault: Profile {
        let row: [ButtonAction] = [
            .mouse(.left), .mouse(.right), .mouse(.middle), .mouse(.back), .mouse(.forward),
            .dpiUp, .dpiDown, .tripleClick, .switchLighting, .switchLighting,
        ]
        let dpis = [1200, 2400, 3500, 5500, 7200, 7200, 7200, 7200]
        let cols: [DPIColor] = [.red, .blue, .green, .magenta, .yellow, .white, .white, .white]
        return Profile(
            name: "Vendor default",
            buttons: Array(repeating: row, count: PC205.modes),
            macros: (1...PC205.macroCount).map { Macro(name: "Macro \($0)") },
            stages: (0..<8).map { GeneralReport.Stage(enabled: $0 < 5, x: dpis[$0], color: cols[$0]) },
            currentStage: 1, xyIndependent: false,
            effect: .breathing, level: 4, lightingFlags: 0,
            colors: [RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255), RGB(255, 255, 0),
                     RGB(0, 255, 255), RGB(255, 0, 255), RGB(255, 255, 255)],
            activeMode: 0, rates: [.hz500, .hz500, .hz500])
    }

    /// Default plus the extra side button sending F13 (Kalista kite key in 3£) in every mode.
    public static var lolDefault: Profile {
        var p = vendorDefault
        p.name = "LoL – side button = F13"
        for m in 0..<PC205.modes { p.buttons[m][likelyExtraSideSlot - 1] = .keyPress(HIDKey.f13) }
        return p
    }

    // MARK: report building

    public func matrixPayload() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: PC205.matrixPayload)
        let used = Set(buttons.flatMap { $0 }.compactMap { a -> Int? in
            if case let .macro(i, _) = a { return i } else { return nil }
        })
        for i in used where (1...PC205.macroCount).contains(i) && i <= macros.count {
            let data = macros[i - 1].encode()
            out.replaceSubrange((i - 1) * PC205.macroSize ..< i * PC205.macroSize, with: data)
        }
        var off = PC205.macroAreaSize
        for m in 0..<PC205.modes {
            for s in 0..<PC205.slots {
                let a = m < buttons.count && s < buttons[m].count ? buttons[m][s] : .disabled
                let v = a.entry(slot: s + 1)
                out[off] = UInt8(v & 0xFF)
                out[off + 1] = UInt8((v >> 8) & 0xFF)
                out[off + 2] = UInt8((v >> 16) & 0xFF)
                out[off + 3] = UInt8((v >> 24) & 0xFF)
                off += 4
            }
        }
        return out
    }

    public func matrixFeature() -> [UInt8] { [PC205.matrixReportID] + matrixPayload() }

    /// Applies DPI and lighting settings onto a general report read from the mouse.
    public func apply(to g: inout GeneralReport) {
        g.xyIndependent = xyIndependent
        g.stages = stages
        g.currentStage = currentStage
        g.effect = effect
        g.level = level
        g.lightingFlags = lightingFlags
        g.colors = colors
    }

    public func apply(to m: inout ModeReport) {
        m.activeMode = activeMode
        for i in 0..<PC205.modes { m.setRate(i < rates.count ? rates[i] : .hz500, mode: i) }
    }

    /// Imports DPI / lighting state from the mouse.
    public mutating func load(from g: GeneralReport) {
        xyIndependent = g.xyIndependent
        stages = g.stages.enumerated().map { i, s in
            var s = s
            if s.x == 0 { s.x = stages[i].x; s.y = stages[i].y }
            return s
        }
        currentStage = g.currentStage
        effect = g.effect
        level = g.level
        lightingFlags = g.lightingFlags
        colors = g.colors
    }

    public mutating func load(from m: ModeReport) {
        activeMode = m.activeMode
        rates = (0..<PC205.modes).map { m.rate(mode: $0) }
    }

    /// Imports button mapping / macros from a matrix payload (if the mouse supports reading it back).
    public mutating func load(matrixPayload p: [UInt8]) {
        guard p.count >= PC205.matrixPayload else { return }
        var off = PC205.macroAreaSize
        for m in 0..<PC205.modes {
            for s in 0..<PC205.slots {
                let v = UInt32(p[off]) | UInt32(p[off + 1]) << 8 | UInt32(p[off + 2]) << 16 | UInt32(p[off + 3]) << 24
                buttons[m][s] = ButtonAction.decode(v)
                off += 4
            }
        }
        for i in 0..<PC205.macroCount {
            let chunk = Array(p[i * PC205.macroSize ..< (i + 1) * PC205.macroSize])
            if chunk.contains(where: { $0 != 0 }) { macros[i] = Macro.decode(chunk, name: macros[i].name) }
        }
    }
}
