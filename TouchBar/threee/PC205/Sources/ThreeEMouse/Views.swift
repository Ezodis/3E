import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PC205Core

// MARK: - Buttons

struct ButtonsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Key mode", selection: $model.editingMode) {
                    ForEach(0..<PC205.modes, id: \.self) { Text("Mode \($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 280)
                Spacer()
                Button("Copy this mode to all modes") {
                    let row = model.profile.buttons[model.editingMode]
                    for m in 0..<PC205.modes { model.profile.buttons[m] = row }
                }
                Button("Vendor defaults") { model.profile.buttons = Profile.vendorDefault.buttons }
            }
            Text("Each slot can do anything, including the extra side button the Windows app only allows macros on. For 3£ LoL kiting set that button to Key → F13 (or Pause). Not sure which slot it is? Use Identify buttons.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(0..<PC205.slots, id: \.self) { s in
                    HStack(alignment: .top) {
                        Text(Profile.slotNames[s]).frame(width: 190, alignment: .leading)
                        ActionEditor(action: $model.profile.buttons[model.editingMode][s], macros: model.profile.macros)
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                if model.identifying {
                    Button("Stop identifying & restore") { model.stopIdentify() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Identify buttons…") { model.startIdentify() }.disabled(!model.connected)
                }
                if let r = model.identifyResult { Text(r).font(.callout) }
                Spacer()
                Button("Apply buttons & macros") { model.apply(.matrix) }.disabled(!model.connected)
            }
        }
        .padding(6)
    }
}

enum ActionKind: String, CaseIterable, Identifiable {
    case mouse = "Mouse button", double = "Double click", triple = "Triple click", key = "Key / combo",
         fire = "Fire key (auto-repeat)", media = "Multimedia", dpiUp = "DPI +", dpiDown = "DPI −",
         dpiLoop = "DPI loop", dpiLock = "DPI lock", rate = "Switch polling rate",
         lighting = "Switch lighting effect", macro = "Macro", disabled = "Disabled", raw = "Raw value"
    var id: String { rawValue }

    init(_ a: ButtonAction) {
        switch a {
        case .mouse: self = .mouse
        case .doubleClick: self = .double
        case .tripleClick: self = .triple
        case .key: self = .key
        case .fire: self = .fire
        case .media: self = .media
        case .dpiUp: self = .dpiUp
        case .dpiDown: self = .dpiDown
        case .dpiLoop: self = .dpiLoop
        case .dpiLock: self = .dpiLock
        case .switchPollingRate: self = .rate
        case .switchLighting: self = .lighting
        case .macro: self = .macro
        case .disabled: self = .disabled
        case .raw: self = .raw
        }
    }

    var defaultAction: ButtonAction {
        switch self {
        case .mouse: return .mouse(.left)
        case .double: return .doubleClick
        case .triple: return .tripleClick
        case .key: return .keyPress(HIDKey.f13)
        case .fire: return .fire(key: 0xF0, intervalMs: 50, count: 3)
        case .media: return .media(.playPause)
        case .dpiUp: return .dpiUp
        case .dpiDown: return .dpiDown
        case .dpiLoop: return .dpiLoop
        case .dpiLock: return .dpiLock(dpi: 800)
        case .rate: return .switchPollingRate
        case .lighting: return .switchLighting
        case .macro: return .macro(index: 1, mode: .count)
        case .disabled: return .disabled
        case .raw: return .raw(0x0150)
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
            ForEach(HIDKey.all) { k in
                Text(k.name + (HIDKey.vendorTableContains(k.usage) ? "" : " *")).tag(k.usage)
            }
        }
        .frame(maxWidth: 220)
    }
}

struct ActionEditor: View {
    @Binding var action: ButtonAction
    let macros: [Macro]

    var kind: Binding<ActionKind> {
        Binding(get: { ActionKind(action) }, set: { if $0 != ActionKind(action) { action = $0.defaultAction } })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Picker("", selection: kind) {
                ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
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
                ForEach(MouseButton.allCases) { Text($0.name).tag($0) }
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
                ForEach(MediaKey.allCases) { Text($0.name).tag($0) }
            }.labelsHidden().frame(width: 180)
        case .dpiLock(let d):
            Picker("", selection: Binding(get: { d }, set: { action = .dpiLock(dpi: $0) })) {
                ForEach(PC205.dpiTable, id: \.self) { Text("\($0) DPI").tag($0) }
            }.labelsHidden().frame(width: 140)
        case let .macro(i, mode):
            Picker("", selection: Binding(get: { i }, set: { action = .macro(index: $0, mode: mode) })) {
                ForEach(1...PC205.macroCount, id: \.self) { n in
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
        Form {
            Toggle("Independent X / Y DPI", isOn: $model.profile.xyIndependent)
            Picker("Current stage", selection: $model.profile.currentStage) {
                ForEach(0..<PC205.dpiStages, id: \.self) { Text("Stage \($0 + 1)").tag($0) }
            }
            ForEach(0..<PC205.dpiStages, id: \.self) { i in
                HStack {
                    Toggle("Stage \(i + 1)", isOn: $model.profile.stages[i].enabled).frame(width: 110, alignment: .leading)
                    Picker(model.profile.xyIndependent ? "X" : "DPI", selection: $model.profile.stages[i].x) {
                        ForEach(PC205.dpiTable, id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 160)
                    if model.profile.xyIndependent {
                        Picker("Y", selection: $model.profile.stages[i].y) {
                            ForEach(PC205.dpiTable, id: \.self) { Text("\($0)").tag($0) }
                        }.frame(width: 140)
                    }
                    Picker("Colour", selection: $model.profile.stages[i].color) {
                        ForEach(DPIColor.allCases) { c in
                            Text(c.name).tag(c)
                        }
                    }.frame(width: 170)
                    Circle().fill(Color(rgb: model.profile.stages[i].color.rgb)).frame(width: 14, height: 14)
                }
                .onChange(of: model.profile.stages[i].x) { v in
                    if !model.profile.xyIndependent { model.profile.stages[i].y = v }
                }
            }
            HStack {
                Spacer()
                Button("Apply DPI & lighting") {
                    if !model.profile.stages.contains(where: \.enabled) { model.profile.stages[0].enabled = true }
                    model.apply(.general)
                }.disabled(!model.connected)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lighting

struct LightingView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Picker("Effect", selection: $model.profile.effect) {
                ForEach(LightingEffect.allCases) { e in
                    Text(e.name + (e.hiddenByVendor ? " (hidden in vendor app)" : "")).tag(e)
                }
            }
            Stepper("\(model.profile.effect == .steady ? "Brightness" : "Speed") level: \(model.profile.level)",
                    value: $model.profile.level, in: 1...8)
            Toggle("Random / colourful variant", isOn: Binding(
                get: { model.profile.lightingFlags & 0x80 != 0 },
                set: { model.profile.lightingFlags = ($0 ? 0x80 : 0) | (model.profile.lightingFlags & 0x7F) }))
            Stepper("Colours used: \(model.profile.lightingFlags & 0x07)", value: Binding(
                get: { Int(model.profile.lightingFlags & 0x07) },
                set: { model.profile.lightingFlags = (model.profile.lightingFlags & 0xF8) | UInt8($0) }), in: 0...7)
            ForEach(0..<7, id: \.self) { i in
                ColorPicker("Colour \(i + 1)", selection: Binding(
                    get: { Color(rgb: model.profile.colors[i]) },
                    set: { model.profile.colors[i] = $0.rgb }), supportsOpacity: false)
            }
            HStack {
                Spacer()
                Button("Apply DPI & lighting") { model.apply(.general) }.disabled(!model.connected)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Polling / modes

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Picker("Active key mode", selection: $model.profile.activeMode) {
                ForEach(0..<PC205.modes, id: \.self) { Text("Mode \($0 + 1)").tag($0) }
            }
            ForEach(0..<PC205.modes, id: \.self) { m in
                Picker("Polling rate – mode \(m + 1)", selection: $model.profile.rates[m]) {
                    ForEach(PollingRate.allCases) { Text("\($0.hz) Hz").tag($0) }
                }
            }
            if model.device.mode == nil {
                Text("The mode/polling-rate collection (feature report 8) was not found, so these settings can't be applied.")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Apply polling rate & mode") { model.apply(.mode) }.disabled(!model.connected)
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
        HSplitView {
            List(selection: $selected) {
                ForEach(0..<model.profile.macros.count, id: \.self) { i in
                    Text("\(i + 1). \(model.profile.macros[i].name)").tag(i)
                }
            }
            .frame(minWidth: 180, maxWidth: 220)
            MacroEditor(macro: $model.profile.macros[selected])
                .padding(6)
        }
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro
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
                Stepper("Delay \(newDelay) ms", value: $newDelay, in: 0...Macro.maxDelay, step: 10)
                Button("+ Tap") { macro.events += Macro.tap(newKey, holdMs: newDelay, gapMs: newDelay) }
                Button("+ Press") { macro.events.append(MacroEvent(key: newKey, press: true, delayMs: newDelay)) }
                Button("+ Release") { macro.events.append(MacroEvent(key: newKey, press: false, delayMs: newDelay)) }
                Button("Remove last") { if !macro.events.isEmpty { macro.events.removeLast() } }
                Button("Clear") { macro.events.removeAll() }
            }
            let used = macro.encode().count
            Text("Encoded size \(used) bytes (128 max per macro, up to 8 macros). Assign it to a button in the Buttons tab, then Apply.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Export profile…") { exportProfile() }
                Button("Import profile…") { importProfile() }
                Button("Reset to vendor defaults") { model.profile = .vendorDefault }
                Button("LoL preset (side = F13)") { model.profile = .lolDefault }
            }
            if let g = model.lastGeneral {
                Text("General report (ID 4): " + g.featureBytes.map { String(format: "%02X", $0) }.joined(separator: " "))
                    .font(.caption.monospaced()).textSelection(.enabled)
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
        p.nameFieldStringValue = "PC205-profile.json"
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
