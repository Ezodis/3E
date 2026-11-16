import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MouseCore

// Every page is built from model.caps (MouseCapabilities), so a new mouse needs no view changes.

// MARK: - Buttons

struct ButtonsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        let mode = min(model.editingMode, max(0, model.profile.buttons.count - 1))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if caps.modes > 1 {
                    Picker("Key mode", selection: $model.editingMode) {
                        ForEach(0..<caps.modes, id: \.self) { Text("Mode \($0 + 1)").tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 280)
                    Button("Copy this mode to all modes") {
                        let row = model.profile.buttons[mode]
                        for m in model.profile.buttons.indices { model.profile.buttons[m] = row }
                    }
                }
                Spacer()
                Button("Defaults") { if let d = model.driver { model.profile.buttons = d.defaultProfile().buttons } }
            }
            if caps.extraSideSlot > 0 {
                Text("Every slot can do anything, including the extra side button (\(caps.slotName(caps.extraSideSlot))) the vendor app limits to macros. For 3£ LoL kiting set it to Key → F13 (or Pause). Not sure which slot a button is? Use Identify buttons.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach(0..<caps.slots, id: \.self) { s in
                    HStack(alignment: .top) {
                        Text(caps.slotName(s + 1)).frame(width: 190, alignment: .leading)
                        ActionEditor(action: $model.profile.buttons[mode][s], caps: caps, macros: model.profile.macros)
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                if !caps.identifySlots.isEmpty && caps.actions.contains(.key) {
                    if model.identifying {
                        Button("Stop identifying & restore") { model.stopIdentify() }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Identify buttons…") { model.startIdentify() }.disabled(!model.connected)
                    }
                    if let r = model.identifyResult { Text(r).font(.callout) }
                }
                Spacer()
                Button(caps.hasMacros ? "Apply buttons & macros" : "Apply buttons") { model.apply(.buttons) }.disabled(!model.connected)
            }
        }
        .padding(6)
    }
}

extension ActionKind {
    func defaultAction(_ caps: MouseCapabilities) -> ButtonAction {
        switch self {
        case .mouse: return .mouse(.left)
        case .doubleClick: return .doubleClick
        case .tripleClick: return .tripleClick
        case .key: return .keyPress(HIDKey.f13)
        case .fire: return .fire(key: 0xF0, intervalMs: 50, count: 3)
        case .media: return .media(caps.mediaKeys.first ?? .playPause)
        case .dpiUp: return .dpiUp
        case .dpiDown: return .dpiDown
        case .dpiLoop: return .dpiLoop
        case .dpiLock: return .dpiLock(dpi: caps.dpiValues.first ?? 800)
        case .switchPollingRate: return .switchPollingRate
        case .switchLighting: return .switchLighting
        case .macro: return .macro(index: 1, mode: .count)
        case .disabled: return .disabled
        case .raw: return .raw(0)
        }
    }
}

struct KeyPicker: View {
    let title: String
    @Binding var usage: UInt8
    var allowNone = false
    var body: some View {
        Picker(title, selection: $usage) {
            if allowNone { Text("—").tag(UInt8(0)) }
            ForEach(HIDKey.all) { k in Text(k.name).tag(k.usage) }
        }
        .frame(maxWidth: 220)
    }
}

struct ActionEditor: View {
    @Binding var action: ButtonAction
    let caps: MouseCapabilities
    let macros: [Macro]

    var kinds: [ActionKind] { caps.actions.contains(action.kind) ? caps.actions : caps.actions + [action.kind] }
    var kind: Binding<ActionKind> {
        Binding(get: { action.kind }, set: { if $0 != action.kind { action = $0.defaultAction(caps) } })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Picker("", selection: kind) {
                ForEach(kinds) { Text($0.name).tag($0) }
            }
            .labelsHidden().frame(width: 190)
            details
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder var details: some View {
        switch action {
        case .mouse(let b):
            Picker("", selection: Binding(get: { b }, set: { action = .mouse($0) })) {
                ForEach(caps.mouseButtons) { Text($0.name).tag($0) }
            }.labelsHidden().frame(width: 160)
        case let .key(m, k, k2):
            ModifierToggles(mods: Binding(get: { m }, set: { action = .key(modifiers: $0, key: k, key2: k2) }))
            KeyPicker(title: "", usage: Binding(get: { k }, set: { action = .key(modifiers: m, key: $0, key2: k2) }), allowNone: true)
                .labelsHidden()
            KeyPicker(title: "+", usage: Binding(get: { k2 }, set: { action = .key(modifiers: m, key: k, key2: $0) }), allowNone: true)
        case let .fire(k, i, c):
            KeyPicker(title: "", usage: Binding(get: { k }, set: { action = .fire(key: $0, intervalMs: i, count: c) })).labelsHidden()
            Stepper("×\(c)", value: Binding(get: { Int(c) }, set: { action = .fire(key: k, intervalMs: i, count: UInt8($0)) }), in: 1...255)
            Stepper("\(i) ms", value: Binding(get: { Int(i) }, set: { action = .fire(key: k, intervalMs: UInt8($0), count: c) }), in: 5...255)
        case .media(let mk):
            Picker("", selection: Binding(get: { mk }, set: { action = .media($0) })) {
                ForEach(caps.mediaKeys) { Text($0.name).tag($0) }
            }.labelsHidden().frame(width: 180)
        case .dpiLock(let d):
            Picker("", selection: Binding(get: { d }, set: { action = .dpiLock(dpi: $0) })) {
                ForEach(caps.dpiValues, id: \.self) { Text("\($0) DPI").tag($0) }
            }.labelsHidden().frame(width: 140)
        case let .macro(i, mode):
            Picker("", selection: Binding(get: { i }, set: { action = .macro(index: $0, mode: mode) })) {
                ForEach(1...max(1, caps.macroCount), id: \.self) { n in
                    Text(n <= macros.count ? "\(n): \(macros[n - 1].name)" : "Macro \(n)").tag(n)
                }
            }.labelsHidden().frame(width: 180)
            Picker("", selection: Binding(get: { mode }, set: { action = .macro(index: i, mode: $0) })) {
                ForEach(MacroRepeat.allCases) { Text($0.name).tag($0) }
            }.labelsHidden().frame(width: 170)
        case .raw(let v):
            TextField("hex", text: Binding(
                get: { String(format: "%08X", v) },
                set: { if let n = UInt32($0, radix: 16) { action = .raw(n) } }))
                .frame(width: 110).font(.body.monospaced())
        default:
            EmptyView()
        }
    }
}

struct ModifierToggles: View {
    @Binding var mods: Modifiers
    var body: some View {
        HStack(spacing: 2) {
            toggle("⌃", .leftControl)
            toggle("⌥", .leftOption)
            toggle("⇧", .leftShift)
            toggle("⌘", .leftCommand)
        }
    }
    func toggle(_ t: String, _ m: Modifiers) -> some View {
        Toggle(t, isOn: Binding(get: { mods.contains(m) }, set: { if $0 { mods.insert(m) } else { mods.remove(m) } }))
            .toggleStyle(.button)
    }
}

// MARK: - DPI

struct DPIView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        let xy = caps.dpiXY && model.profile.xyIndependent
        Form {
            if caps.dpiXY { Toggle("Independent X / Y DPI", isOn: $model.profile.xyIndependent) }
            Picker("Current stage", selection: $model.profile.currentStage) {
                ForEach(0..<caps.dpiStages, id: \.self) { Text("Stage \($0 + 1)").tag($0) }
            }
            ForEach(0..<caps.dpiStages, id: \.self) { i in
                HStack {
                    Toggle("Stage \(i + 1)", isOn: $model.profile.stages[i].enabled).frame(width: 110, alignment: .leading)
                    Picker(xy ? "X" : "DPI", selection: Binding(
                        get: { model.profile.stages[i].x },
                        set: { model.profile.stages[i].x = $0; if !xy { model.profile.stages[i].y = $0 } })) {
                        ForEach(caps.dpiValues, id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 160)
                    if xy {
                        Picker("Y", selection: $model.profile.stages[i].y) {
                            ForEach(caps.dpiValues, id: \.self) { Text("\($0)").tag($0) }
                        }.frame(width: 140)
                    }
                    if !caps.dpiColorNames.isEmpty {
                        Picker("Colour", selection: $model.profile.stages[i].color) {
                            ForEach(caps.dpiColorNames.indices, id: \.self) { Text(caps.dpiColorNames[$0]).tag($0) }
                        }.frame(width: 170)
                        let c = model.profile.stages[i].color
                        if c < caps.dpiColorValues.count {
                            Circle().fill(Color(rgb: caps.dpiColorValues[c])).frame(width: 14, height: 14)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Apply DPI") { model.apply(.dpi) }.disabled(!model.connected)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lighting

struct LightingView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        Form {
            Picker("Effect", selection: $model.profile.effect) {
                ForEach(caps.lightingEffects.indices, id: \.self) { i in
                    Text(caps.lightingEffects[i] + (caps.lightingEffectsHidden.contains(i) ? " (hidden in vendor app)" : "")).tag(i)
                }
            }
            if caps.lightingLevelMax > 0 {
                Stepper("Speed / brightness level: \(model.profile.level)", value: $model.profile.level, in: 1...caps.lightingLevelMax)
            }
            if caps.lightingRandom { Toggle("Random / colourful variant", isOn: $model.profile.lightingRandom) }
            if caps.lightingColors > 0 {
                Stepper("Colours used: \(model.profile.lightingColorCount)", value: $model.profile.lightingColorCount, in: 0...caps.lightingColors)
            }
            ForEach(0..<min(caps.lightingColors, model.profile.colors.count), id: \.self) { i in
                ColorPicker("Colour \(i + 1)", selection: Binding(
                    get: { Color(rgb: model.profile.colors[i]) },
                    set: { model.profile.colors[i] = $0.rgb }), supportsOpacity: false)
            }
            HStack {
                Spacer()
                Button("Apply lighting") { model.apply(.lighting) }.disabled(!model.connected)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Polling / modes

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        Form {
            if caps.modes > 1 {
                Picker("Active key mode", selection: $model.profile.activeMode) {
                    ForEach(0..<caps.modes, id: \.self) { Text("Mode \($0 + 1)").tag($0) }
                }
            }
            ForEach(0..<min(max(1, caps.modes), model.profile.ratesHz.count), id: \.self) { m in
                Picker(caps.modes > 1 ? "Polling rate – mode \(m + 1)" : "Polling rate", selection: $model.profile.ratesHz[m]) {
                    ForEach(caps.pollingRatesHz, id: \.self) { Text("\($0) Hz").tag($0) }
                }
            }
            HStack {
                Spacer()
                Button("Apply polling rate") { model.apply(.polling) }.disabled(!model.connected)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Macros

struct MacrosView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected = 0
    var body: some View {
        let count = min(model.caps.macroCount, model.profile.macros.count)
        HSplitView {
            List(selection: $selected) {
                ForEach(0..<count, id: \.self) { i in
                    Text("\(i + 1). \(model.profile.macros[i].name)").tag(i)
                }
            }
            .frame(minWidth: 180, maxWidth: 220)
            if selected < count {
                MacroEditor(macro: $model.profile.macros[selected], caps: model.caps).padding(6)
            }
        }
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro
    let caps: MouseCapabilities
    @State private var newKey: UInt8 = 0x04
    @State private var newDelay = 20
    var body: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $macro.name)
            Stepper("Repeat count (for “Repeat N times”): \(macro.repeatCount)",
                    value: Binding(get: { Int(macro.repeatCount) }, set: { macro.repeatCount = UInt16($0) }), in: 1...65535)
            Table(macro.events) {
                TableColumn("Key") { e in Text(HIDKey.name(e.key)) }
                TableColumn("Action") { e in Text(e.press ? "Press ↓" : "Release ↑") }
                TableColumn("Delay after (ms)") { e in Text("\(e.delayMs)") }
            }
            HStack {
                KeyPicker(title: "Key", usage: $newKey)
                Stepper("Delay \(newDelay) ms", value: $newDelay, in: 0...max(1, caps.macroMaxDelayMs), step: 10)
                Button("+ Tap") { macro.events += Macro.tap(newKey, holdMs: newDelay, gapMs: newDelay) }
                Button("+ Press") { macro.events.append(MacroEvent(key: newKey, press: true, delayMs: newDelay)) }
                Button("+ Release") { macro.events.append(MacroEvent(key: newKey, press: false, delayMs: newDelay)) }
                Button("Remove last") { if !macro.events.isEmpty { macro.events.removeLast() } }
                Button("Clear") { macro.events.removeAll() }
            }
            Text("Up to \(caps.macroCount) macros of \(caps.macroBytes) bytes. Assign a macro to a button in the Buttons tab, then Apply.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supported mice: " + MouseDevices.supported.map { String(format: "%@ (%04X:%04X)", $0.name, $0.vendorID, $0.productID) }.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
            if let d = model.driver {
                HStack {
                    Button("Export profile…") { exportProfile() }
                    Button("Import profile…") { importProfile() }
                    Button("Reset to defaults") { model.resetToDefaults() }
                }
                ForEach(d.diagnostics(), id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
            }
            Text("Log").font(.headline)
            ScrollView {
                Text(model.logLines.joined(separator: "\n"))
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .padding(6)
    }

    func exportProfile() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "\(model.driver?.id ?? "mouse")-profile.json"
        if p.runModal() == .OK, let url = p.url { try? model.exportProfile(to: url) }
    }

    func importProfile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url { try? model.importProfile(from: url) }
    }
}

// MARK: - Colour helpers

extension Color {
    init(rgb: RGB) { self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255) }
    var rgb: RGB {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return RGB(UInt8(max(0, min(255, c.redComponent * 255))),
                   UInt8(max(0, min(255, c.greenComponent * 255))),
                   UInt8(max(0, min(255, c.blueComponent * 255))))
    }
}
