import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MouseCore
import MouseHID

// 3£ Mouse window laid out like the vendor configurator (OemDrv.exe): 1030×662 skinned window, key list
// on the left, mouse picture with clickable numbered buttons, DPI / Lighting / Mouse Parameter / Polling
// Rate accordion on the right, Mode and driver buttons at the bottom, function picker and macro editor.
// Images come from the user's own vendor skin (VendorSkin); without it the same layout is drawn.
// Everything is built from MouseCapabilities. Windows twin: Windows/Mouse/MouseWindow.cs.

enum Skin {
    static let text = Color(red: 180 / 255, green: 180 / 255, blue: 180 / 255)
    static let over = Color.white
    static let down = Color(red: 230 / 255, green: 0, blue: 18 / 255)
    static let listBack = Color(red: 39 / 255, green: 39 / 255, blue: 39 / 255)
    static let listItem = Color(red: 0, green: 218 / 255, blue: 233 / 255)
    static let listDown = Color(red: 1, green: 232 / 255, blue: 6 / 255)
    static let popBack = Color(red: 6 / 255, green: 6 / 255, blue: 7 / 255)
    static let popFrame = Color(white: 100 / 255)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

extension View {
    /// Absolute placement in window coordinates (vendor layout).
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { offset(x: x, y: y) }
}

struct SkinImage: View {
    let image: NSImage
    var body: some View { Image(nsImage: image).resizable().interpolation(.none).frame(width: image.size.width, height: image.size.height) }
}

/// Vendor-style button: normal / hover / down images, caption in Btn_txt_clr_nr/ov/dn.
struct SkinButton: View {
    @EnvironmentObject var model: AppModel
    let nr: String, ov: String, dn: String
    let text: String
    let w: CGFloat, h: CGFloat
    var down = false
    var leftAlign = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        ZStack(alignment: leftAlign ? .leading : .center) {
            if let img = model.skin?.image(down ? dn : (hover ? ov : nr)) {
                Image(nsImage: img).resizable().frame(width: w, height: h)
            } else {
                RoundedRectangle(cornerRadius: 3).fill(down ? Color(red: 0.24, green: 0.03, blue: 0.04) : Color(white: 0.105))
                RoundedRectangle(cornerRadius: 3).stroke(down ? Skin.down : (hover ? Skin.over : Color(white: 0.28)), lineWidth: 1)
            }
            Text(text).font(Skin.font(h <= 16 ? 11 : 12)).lineLimit(1)
                .foregroundColor(down ? Skin.down : (hover ? Skin.over : Skin.text))
                .padding(.horizontal, leftAlign ? 12 : 3)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}

struct SkinCheck: View {
    @EnvironmentObject var model: AppModel
    let text: String
    @Binding var on: Bool
    var body: some View {
        HStack(spacing: 6) {
            if let img = model.skin?.image(on ? "check_dn.png" : "check_nr.png") { SkinImage(image: img) }
            else { Rectangle().fill(on ? Skin.down : Color(white: 0.08)).overlay(Rectangle().stroke(Skin.text)).frame(width: 11, height: 11) }
            if !text.isEmpty { Text(text).font(Skin.font(11)).foregroundColor(Skin.text) }
        }
        .contentShape(Rectangle())
        .onTapGesture { on.toggle() }
    }
}

struct SkinRadio: View {
    @EnvironmentObject var model: AppModel
    let text: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            if let img = model.skin?.image(on ? "radio_dn.png" : "radio_nr.png") { SkinImage(image: img) }
            else {
                ZStack {
                    Circle().stroke(Skin.text, lineWidth: 1)
                    if on { Circle().fill(Skin.down).frame(width: 7, height: 7) }
                }.frame(width: 15, height: 15)
            }
            if !text.isEmpty { Text(text).font(Skin.font(11.5)).foregroundColor(on ? Skin.listDown : Skin.text) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// Lets the borderless window be dragged by its top strip, like the vendor window.
struct DragStrip: NSViewRepresentable {
    final class V: NSView { override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) } }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - main window

struct VendorWindow: View {
    @EnvironmentObject var model: AppModel
    var caps: MouseCapabilities { model.caps }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            DragStrip().frame(width: 910, height: 36).at(20, 4)
            Text("3£ Mouse" + (model.driver.map { " – " + $0.displayName } ?? ""))
                .font(Skin.font(14, .semibold)).foregroundColor(Skin.text).at(40, 14)
            SkinButton(nr: "min_nr.png", ov: "min_ov.png", dn: "min_ov.png", text: "–", w: 15, h: 15) { NSApp.keyWindow?.miniaturize(nil) }.at(940, 21)
            SkinButton(nr: "exit_nr.png", ov: "exit_ov.png", dn: "exit_ov.png", text: "×", w: 15, h: 15) { NSApp.keyWindow?.close() }.at(965, 21)
            if model.driver == nil {
                noDevice
            } else {
                if caps.hasButtons { KeyList() }
                MousePicture()
                Accordion().at(743, 41)
                BottomBar()
                Text(model.status).font(Skin.font(11)).foregroundColor(Skin.text).lineLimit(2).frame(width: 640, alignment: .leading).at(300, 626)
            }
            if model.pickerSlot != nil || model.showMacroEditor || model.showInfo {
                Color.black.opacity(0.55).frame(width: 1030, height: 662)
                Group {
                    if let slot = model.pickerSlot { FunctionPicker(slot: slot) }
                    else if model.showMacroEditor { MacroEditor() }
                    else { InfoPanel() }
                }
                .frame(width: 1030, height: 662)
            }
        }
        .frame(width: 1030, height: 662, alignment: .topLeading)
        .background(Color.black)
    }

    @ViewBuilder var background: some View {
        if let bg = model.skin?.image("main_nr.png") {
            SkinImage(image: bg)
        } else {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 85 / 255)).frame(width: 1030, height: 662)
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(red: 14 / 255, green: 15 / 255, blue: 17 / 255), Color(red: 6 / 255, green: 7 / 255, blue: 8 / 255)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 1010, height: 646).at(10, 8)
                ForEach([108.0, 498.0], id: \.self) { y in
                    ForEach(0..<4, id: \.self) { i in
                        Stripe(flip: false).fill(Skin.down).frame(width: 22, height: 10).at(10, y + Double(i) * 14)
                        Stripe(flip: true).fill(Skin.down).frame(width: 22, height: 10).at(998, y + Double(i) * 14)
                    }
                }
            }
        }
    }

    var noDevice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No supported mouse connected.").font(Skin.font(16, .semibold)).foregroundColor(Skin.over)
            Text("Supported: " + MouseDevices.supported.map { String(format: "%@ (%04X:%04X)", $0.name, $0.vendorID, $0.productID) }.joined(separator: ", ") + ". Plug the mouse in and click Reconnect.")
                .font(Skin.font(11)).foregroundColor(Skin.text).frame(width: 360, alignment: .leading)
            SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "Reconnect", w: 92, h: 27) { model.connect() }
        }
        .at(340, 260)
    }
}

struct Stripe: Shape {
    let flip: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if flip { p.move(to: CGPoint(x: r.maxX, y: 0)); p.addLine(to: CGPoint(x: 0, y: r.height * 0.6)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.addLine(to: CGPoint(x: r.maxX, y: r.height * 0.4)) }
        else { p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: r.height * 0.6)); p.addLine(to: CGPoint(x: r.maxX, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height * 0.4)) }
        p.closeSubpath()
        return p
    }
}

func shortLabel(_ a: ButtonAction) -> String {
    switch a {
    case let .key(m, k, k2): return String(ButtonAction.key(modifiers: m, key: k, key2: k2).label.dropFirst(5))
    case .mouse(let b): return b.name
    case let .macro(i, _): return "Macro \(i)"
    default: return a.label
    }
}

// Left: key list (window rect 30,40–270,300; button2 179×25 at x=75, y=50+31·i).
struct KeyList: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        let mode = min(model.editingMode, max(0, model.profile.buttons.count - 1))
        ForEach(0..<caps.shownSlots, id: \.self) { s in
            SkinButton(nr: "button2_nr.png", ov: "button2_ov.png", dn: "button2_ov.png",
                       text: "\(s + 1)   " + shortLabel(model.profile.buttons[mode][s]), w: 179, h: 25, down: model.selectedSlot == s) {
                model.selectedSlot = s; model.pickerSlot = s
            }
            .help(caps.slotName(s + 1) + ": " + model.profile.buttons[mode][s].label)
            .at(75, 50 + 31 * CGFloat(s))
        }
        if caps.extraSideSlot > 0 && caps.extraSideSlot <= caps.shownSlots {
            let side = model.profile.buttons[mode][caps.extraSideSlot - 1]
            let f13 = side == .keyPress(HIDKey.f13)
            Text("Button \(caps.extraSideSlot) (extra side button) can do anything here, not only macros. 3£ Kalista kite = F13" + (f13 ? " ✓" : " – click to set it."))
                .font(Skin.font(11)).foregroundColor(f13 ? Skin.listItem : Skin.listDown).frame(width: 200, alignment: .leading)
                .at(75, 60 + 31 * CGFloat(caps.shownSlots))
            if !f13 {
                SkinButton(nr: "btn_nr.png", ov: "btn_ov.png", dn: "btn_nr.png", text: "Set F13", w: 100, h: 24) { model.setSideKey(HIDKey.f13) }
                    .at(75, 106 + 31 * CGFloat(caps.shownSlots))
            }
        }
    }
}

// Centre: mouse picture at (340,80), numbered hotspots.
struct MousePicture: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        let mode = min(model.editingMode, max(0, model.profile.buttons.count - 1))
        ZStack(alignment: .topLeading) {
            if let pic = model.skin?.image(caps.mousePicture) { SkinImage(image: pic) }
            else { DrawnMouse().frame(width: 280, height: 440) }
            ForEach(0..<min(caps.shownSlots, caps.buttonHotspots.count), id: \.self) { s in
                if let h = caps.buttonHotspots[s] {
                    Hotspot(number: s + 1, selected: model.selectedSlot == s, drawn: model.skin == nil) {
                        model.selectedSlot = s; model.pickerSlot = s
                    }
                    .help(caps.slotName(s + 1) + ": " + model.profile.buttons[mode][s].label)
                    .at(h.x - 13, h.y - 13)
                }
            }
        }
        .frame(width: 280, height: 440, alignment: .topLeading)
        .at(340, 80)
    }
}

struct Hotspot: View {
    let number: Int
    let selected: Bool
    let drawn: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        ZStack {
            Circle().fill(drawn ? Color(white: 0.92) : Color.clear)
            if drawn { Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundColor(Color(white: 0.08)) }
            Circle().stroke(Skin.down, lineWidth: (selected || hover) ? 2.5 : 0)
        }
        .frame(width: 26, height: 26)
        .contentShape(Circle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}

struct DrawnMouse: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            MouseShape().fill(Color(red: 48 / 255, green: 48 / 255, blue: 50 / 255))
            MouseShape().stroke(LinearGradient(colors: [.blue, .green, .yellow, Skin.down], startPoint: .top, endPoint: .bottom), lineWidth: 3)
            Rectangle().fill(Color(white: 0.08)).frame(width: 2, height: 110).offset(x: 139, y: 22)
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.6, green: 0.12, blue: 0.12)).frame(width: 16, height: 44).offset(x: 131, y: 86)
        }
    }
}

struct MouseShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 140, y: 20))
        p.addCurve(to: CGPoint(x: 38, y: 120), control1: CGPoint(x: 70, y: 20), control2: CGPoint(x: 40, y: 60))
        p.addCurve(to: CGPoint(x: 55, y: 330), control1: CGPoint(x: 30, y: 200), control2: CGPoint(x: 30, y: 260))
        p.addCurve(to: CGPoint(x: 140, y: 420), control1: CGPoint(x: 75, y: 390), control2: CGPoint(x: 110, y: 420))
        p.addCurve(to: CGPoint(x: 225, y: 330), control1: CGPoint(x: 170, y: 420), control2: CGPoint(x: 205, y: 390))
        p.addCurve(to: CGPoint(x: 242, y: 120), control1: CGPoint(x: 250, y: 260), control2: CGPoint(x: 250, y: 200))
        p.addCurve(to: CGPoint(x: 140, y: 20), control1: CGPoint(x: 240, y: 60), control2: CGPoint(x: 210, y: 20))
        p.closeSubpath()
        return p
    }
}

// Right: accordion at x=743 (headers 245×25, 30 px apart; the open panel sits below its header).
struct Accordion: View {
    @EnvironmentObject var model: AppModel
    var panels: [String] {
        var p: [String] = []
        if model.caps.hasDPI { p.append("DPI Setting") }
        if model.caps.hasLighting { p.append("Lighting") }
        p.append("Mouse Parameter")
        if model.caps.hasPolling { p.append("Polling Rate") }
        return p
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(panels.enumerated()), id: \.offset) { i, title in
                SkinButton(nr: "header_nr.png", ov: "header_ov.png", dn: "header_ov2.png",
                           text: (model.openPanel == i ? "▾  " : "▸  ") + title, w: 245, h: 25, down: model.openPanel == i, leftAlign: true) {
                    model.openPanel = model.openPanel == i ? -1 : i
                }
                if model.openPanel == i {
                    Group {
                        switch title {
                        case "DPI Setting": DPIPanel()
                        case "Lighting": LightingPanel()
                        case "Polling Rate": PollingPanel()
                        default: ParameterPanel()
                        }
                    }
                    .frame(width: 245, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 245, alignment: .topLeading)
    }
}

struct DPIPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        let xy = caps.dpiXY && model.profile.xyIndependent
        VStack(alignment: .leading, spacing: 4) {
            if caps.dpiXY { SkinCheck(text: "XY Independent", on: $model.profile.xyIndependent).padding(.leading, 8) }
            ForEach(0..<caps.dpiStages, id: \.self) { i in
                HStack(spacing: 6) {
                    SkinRadio(text: "", on: model.profile.currentStage == i) { model.profile.currentStage = i }
                    SkinCheck(text: "", on: $model.profile.stages[i].enabled)
                    DPISlider(value: Binding(get: { model.profile.stages[i].x },
                                             set: { model.profile.stages[i].x = $0; if !xy { model.profile.stages[i].y = $0 } }), values: caps.dpiValues)
                    if xy {
                        DPISlider(value: $model.profile.stages[i].y, values: caps.dpiValues).frame(width: 60)
                    }
                    Text(xy ? "\(model.profile.stages[i].x)/\(model.profile.stages[i].y)" : "\(model.profile.stages[i].x)")
                        .font(Skin.font(11)).foregroundColor(model.profile.currentStage == i ? Skin.listDown : Skin.text).frame(width: 44, alignment: .leading)
                    if caps.dpiColorNames.count > 1 {
                        let c = model.profile.stages[i].color
                        RoundedRectangle(cornerRadius: 2).fill(c < caps.dpiColorValues.count ? Color(rgb: caps.dpiColorValues[c]) : .black)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Skin.popFrame))
                            .frame(width: 22, height: 14)
                            .help("Colour: " + (c < caps.dpiColorNames.count ? caps.dpiColorNames[c] : "?") + " (click to change)")
                            .onTapGesture { model.profile.stages[i].color = c % (caps.dpiColorNames.count - 1) + 1 }
                    }
                }
                .padding(.leading, 6)
            }
            SkinButton(nr: "btn_nr.png", ov: "btn_ov.png", dn: "btn_nr.png", text: "Apply DPI", w: 100, h: 24) { model.apply(.dpi) }.padding(.leading, 140)
        }
    }
}

struct DPISlider: View {
    @Binding var value: Int
    let values: [Int]
    var body: some View {
        Slider(value: Binding(get: { Double(values.firstIndex(of: value) ?? 0) },
                              set: { value = values[max(0, min(values.count - 1, Int($0.rounded())))] }),
               in: 0...Double(max(1, values.count - 1)), step: 1)
            .controlSize(.mini).tint(Skin.down).frame(width: 100)
    }
}

struct LightingPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Effect").font(Skin.font(11)).foregroundColor(Skin.text)
                Picker("", selection: $model.profile.effect) {
                    ForEach(caps.lightingEffects.indices.filter { !caps.lightingEffectsHidden.contains($0) || $0 == model.profile.effect }, id: \.self) {
                        Text(caps.lightingEffects[$0]).tag($0)
                    }
                }.labelsHidden().frame(width: 170)
            }
            if caps.lightingLevelMax > 0 {
                HStack {
                    Text("Speed / Brightness").font(Skin.font(11)).foregroundColor(Skin.text)
                    Slider(value: Binding(get: { Double(model.profile.level) }, set: { model.profile.level = Int($0) }), in: 1...Double(caps.lightingLevelMax), step: 1)
                        .controlSize(.mini).tint(Skin.down).frame(width: 110)
                }
            }
            if caps.lightingRandom { SkinCheck(text: "Random colour", on: $model.profile.lightingRandom) }
            if caps.lightingColors > 0 {
                HStack(spacing: 4) {
                    Text("Colour").font(Skin.font(11)).foregroundColor(Skin.text)
                    ForEach(0..<min(caps.lightingColors, model.profile.colors.count), id: \.self) { i in
                        ColorPicker("", selection: Binding(get: { Color(rgb: model.profile.colors[i]) }, set: { model.profile.colors[i] = $0.rgb }), supportsOpacity: false)
                            .labelsHidden().frame(width: 22)
                    }
                }
                HStack(spacing: 4) {
                    Text("Colours used").font(Skin.font(11)).foregroundColor(Skin.text)
                    ForEach(0...caps.lightingColors, id: \.self) { n in
                        SkinRadio(text: "\(n)", on: model.profile.lightingColorCount == n) { model.profile.lightingColorCount = n }
                    }
                }
            }
            SkinButton(nr: "btn_nr.png", ov: "btn_ov.png", dn: "btn_nr.png", text: "Apply Lighting", w: 100, h: 24) { model.apply(.lighting) }.padding(.leading, 140)
        }
        .padding(.leading, 8)
    }
}

/// Vendor "Mouse Parameter" changes the OS pointer settings; on a Mac those live in System Settings.
struct ParameterPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pointer speed, scrolling and double-click speed are macOS settings.")
                .font(Skin.font(11)).foregroundColor(Skin.text).frame(width: 225, alignment: .leading)
            SkinButton(nr: "btn_nr.png", ov: "btn_ov.png", dn: "btn_nr.png", text: "Mouse Settings…", w: 120, h: 24) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension") { NSWorkspace.shared.open(url) }
            }
        }
        .padding(.leading, 8)
    }
}

struct PollingPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        let m = min(model.editingMode, max(0, model.profile.ratesHz.count - 1))
        VStack(alignment: .leading, spacing: 8) {
            if caps.modes > 1 { Text("USB polling rate (Hz) – Mode \(m + 1)").font(Skin.font(11)).foregroundColor(Skin.text) }
            HStack(spacing: 12) {
                ForEach(caps.pollingRatesHz, id: \.self) { hz in
                    SkinRadio(text: "\(hz)", on: model.profile.ratesHz.indices.contains(m) && model.profile.ratesHz[m] == hz) { model.profile.ratesHz[m] = hz }
                }
            }
            SkinButton(nr: "btn_nr.png", ov: "btn_ov.png", dn: "btn_nr.png", text: "Apply Rate", w: 100, h: 24) { model.apply(.polling) }.padding(.leading, 140)
        }
        .padding(.leading, 8)
    }
}

// Bottom: Mode (ProfileGpY=500) and driver buttons (DrvGpY=570).
struct BottomBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let caps = model.caps
        ZStack(alignment: .topLeading) {
            if caps.modes > 1 {
                Text("Mode").font(Skin.font(12, .semibold)).foregroundColor(Skin.text).at(45, 478)
                ForEach(0..<caps.modes, id: \.self) { m in
                    SkinButton(nr: "btn_nr.png", ov: "btn_ov.png", dn: "btn_ov.png", text: "Mode \(m + 1)" + (model.profile.activeMode == m ? " ●" : ""), w: 100, h: 24, down: model.editingMode == m) {
                        model.editingMode = m; model.profile.activeMode = m; model.selectedSlot = nil
                    }
                    .help("Edit Mode \(m + 1) and make it the active mode on Apply")
                    .at(45 + 106 * CGFloat(m), 500)
                }
            }
            HStack(spacing: 6) {
                if caps.hasMacros { button("Macro", "Macro Editor") { model.showMacroEditor = true } }
                if !caps.identifySlots.isEmpty && caps.actions.contains(.key) {
                    button(model.identifying ? "Stop" : "Identify", "Find out which number a physical button is") {
                        if model.identifying { model.stopIdentify() } else { model.startIdentify() }
                    }
                }
                button("Restore", "Restore the default settings (press Apply to write them)") { model.resetToDefaults() }
                button("Read", "Read the current settings from the mouse") { model.readFromMouse() }
                button("Apply", "Write all settings to the mouse") { model.apply(.all) }
                button("Info", "Device, skin and log") { model.showInfo = true }
            }
            .at(45, 570)
            if model.identifying, let r = model.identifyResult {
                Text(r).font(Skin.font(11)).foregroundColor(Skin.listDown).frame(width: 300, alignment: .leading).at(640, 540)
            }
        }
    }
    func button(_ text: String, _ tip: String, _ action: @escaping () -> Void) -> some View {
        SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: text, w: 92, h: 27, action: action).help(tip)
    }
}

// MARK: - function picker (pickfundlg.png 540×340)

struct FunctionPicker: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    @State private var draft: ButtonAction = .disabled
    @State private var loaded = false

    var body: some View {
        let caps = model.caps
        let mode = min(model.editingMode, max(0, model.profile.buttons.count - 1))
        ZStack(alignment: .topLeading) {
            if let bg = model.skin?.image("pickfundlg.png") { SkinImage(image: bg) }
            else { RoundedRectangle(cornerRadius: 4).fill(Skin.popBack).overlay(RoundedRectangle(cornerRadius: 4).stroke(Skin.popFrame)).frame(width: 540, height: 340) }
            Text("\(slot + 1). \(caps.slotName(slot + 1))  –  Mode \(mode + 1)").font(Skin.font(13, .semibold)).foregroundColor(Skin.over).at(20, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(caps.actions.filter { $0 != .raw || draft.kind == .raw }) { k in
                        SkinRadio(text: kindName(k), on: draft.kind == k) { if draft.kind != k { draft = k.defaultAction(caps) } }
                    }
                }
            }
            .frame(width: 190, height: 250).at(20, 44)
            ActionDetail(action: $draft).frame(width: 300, height: 210, alignment: .topLeading).at(220, 44)
            if slot + 1 == caps.extraSideSlot {
                Text("Extra side button: the vendor app only allows macros here – 3£ allows anything. For the 3£ Kalista kite choose Key / Key Combination → F13 (or Pause).")
                    .font(Skin.font(11)).foregroundColor(Skin.listDown).frame(width: 300, alignment: .leading).at(220, 258)
            }
            SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "OK", w: 92, h: 27) {
                model.profile.buttons[mode][slot] = draft
                model.status = "Button \(slot + 1): \(draft.label) – press Apply to write it to the mouse."
                model.pickerSlot = nil
            }.at(330, 300)
            SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "Cancel", w: 92, h: 27) { model.pickerSlot = nil }.at(430, 300)
        }
        .frame(width: 540, height: 340, alignment: .topLeading)
        .onAppear { if !loaded { draft = model.profile.buttons[mode][slot]; loaded = true } }
    }
}

func kindName(_ k: ActionKind) -> String {
    switch k {
    case .mouse: return "Mouse button"
    case .doubleClick: return "Double Click"
    case .tripleClick: return "Three Click"
    case .key: return "Key / Key Combination"
    case .fire: return "Fire key"
    case .media: return "Multimedia"
    case .dpiUp: return "DPI+"
    case .dpiDown: return "DPI-"
    case .dpiLoop: return "DPI Loop"
    case .dpiLock: return "DPI Lock"
    case .switchPollingRate: return "Switch Polling Rate"
    case .switchLighting: return "Switch Effect"
    case .disabled: return "Disable"
    case .macro: return "Macro"
    case .raw: return "Raw value"
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

struct ActionDetail: View {
    @EnvironmentObject var model: AppModel
    @Binding var action: ButtonAction
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        let caps = model.caps
        VStack(alignment: .leading, spacing: 6) {
            switch action {
            case .mouse(let b):
                ForEach(caps.mouseButtons) { mb in SkinRadio(text: mb.name, on: b == mb) { action = .mouse(mb) } }
            case let .key(m, k, k2):
                Text("Click Capture and press the key or combination:").font(Skin.font(11)).foregroundColor(Skin.text)
                Text(ButtonAction.key(modifiers: m, key: k, key2: k2).label.dropFirst(5))
                    .font(Skin.font(13, .semibold)).foregroundColor(Skin.listDown)
                    .frame(width: 280, height: 26, alignment: .leading).padding(.leading, 6)
                    .background(Skin.listBack).overlay(Rectangle().stroke(capturing ? Skin.down : Skin.popFrame))
                HStack(spacing: 6) {
                    mini(capturing ? "Stop" : "Capture") { capturing ? stopCapture() : startCapture() }
                    mini("Clear") { action = .key(modifiers: [], key: 0, key2: 0) }
                    mini("F13") { action = .keyPress(HIDKey.f13) }
                    mini("Pause") { action = .keyPress(HIDKey.pause) }
                }
                KeyMenu(title: "Or pick from the list", usage: k) { action = .key(modifiers: m, key: $0, key2: 0) }
            case let .fire(k, i, c):
                KeyMenu(title: "Key: " + HIDKey.name(k), usage: k) { action = .fire(key: $0, intervalMs: i, count: c) }
                Stepper("Loop (1-255): \(c)", value: Binding(get: { Int(c) }, set: { action = .fire(key: k, intervalMs: i, count: UInt8($0)) }), in: 1...255)
                    .font(Skin.font(11)).foregroundColor(Skin.text)
                Stepper("Interval (5-255 ms): \(i)", value: Binding(get: { Int(i) }, set: { action = .fire(key: k, intervalMs: UInt8($0), count: c) }), in: 5...255)
                    .font(Skin.font(11)).foregroundColor(Skin.text)
                Text("The smaller the interval, the faster the key repeats.").font(Skin.font(11)).foregroundColor(Skin.text)
            case .media(let mk):
                LazyVGrid(columns: [GridItem(.fixed(145), alignment: .leading), GridItem(.fixed(145), alignment: .leading)], spacing: 3) {
                    ForEach(caps.mediaKeys) { k in SkinRadio(text: k.name, on: mk == k) { action = .media(k) } }
                }
            case .dpiLock(let d):
                LazyVGrid(columns: [GridItem(.fixed(95), alignment: .leading), GridItem(.fixed(95), alignment: .leading), GridItem(.fixed(95), alignment: .leading)], spacing: 3) {
                    ForEach(caps.dpiValues, id: \.self) { v in SkinRadio(text: "\(v) DPI", on: d == v) { action = .dpiLock(dpi: v) } }
                }
            case let .macro(i, mode):
                Picker("Macro", selection: Binding(get: { i }, set: { action = .macro(index: $0, mode: mode) })) {
                    ForEach(1...max(1, caps.macroCount), id: \.self) { n in
                        Text(n <= model.profile.macros.count ? "\(n). \(model.profile.macros[n - 1].name)" : "Macro \(n)").tag(n)
                    }
                }.frame(width: 260)
                SkinRadio(text: "Specified cycle times", on: mode == .count) { action = .macro(index: i, mode: .count) }
                SkinRadio(text: "Cycle until the key released", on: mode == .whileHeld) { action = .macro(index: i, mode: .whileHeld) }
                SkinRadio(text: "Cycle until any key pressed", on: mode == .untilKeyPress) { action = .macro(index: i, mode: .untilKeyPress) }
                mini("Macro Editor…") { model.pickerSlot = nil; model.showMacroEditor = true }
            case .raw(let v):
                TextField("hex", text: Binding(get: { String(format: "%08X", v) }, set: { if let n = UInt32($0, radix: 16) { action = .raw(n) } }))
                    .frame(width: 110).font(.body.monospaced())
            default:
                Text(kindName(action.kind) + " – no options.").font(Skin.font(11)).foregroundColor(Skin.text)
            }
        }
        .onDisappear { stopCapture() }
    }

    func mini(_ text: String, _ a: @escaping () -> Void) -> some View {
        SkinButton(nr: "dot_nr.png", ov: "dot_ov.png", dn: "dot_nr.png", text: text, w: max(56, CGFloat(text.count) * 7 + 14), h: 20, action: a)
    }

    func startCapture() {
        capturing = true
        action = .key(modifiers: [], key: 0, key2: 0)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { ev in
            let u = HIDKey.fromMacKeyCode(ev.keyCode)
            guard u != 0, case let .key(m, k, k2) = action else { return nil }
            let bit = HIDKey.modifierBit(u)
            if bit != 0 { if ev.type == .flagsChanged { action = .key(modifiers: m.union(Modifiers(rawValue: bit)), key: k, key2: k2) } }
            else if ev.type == .keyDown && !ev.isARepeat { action = k == 0 ? .key(modifiers: m, key: u, key2: 0) : .key(modifiers: m, key: k, key2: u) }
            return nil
        }
    }

    func stopCapture() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        capturing = false
    }
}

struct KeyMenu: View {
    let title: String
    let usage: UInt8
    let chosen: (UInt8) -> Void
    var body: some View {
        Menu(title) { ForEach(HIDKey.all) { k in Button(k.name) { chosen(k.usage) } } }.frame(width: 200)
    }
}

// MARK: - macro editor (macro_nr.png 767×418)

struct MacroEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var index = 0
    @State private var recording = false
    @State private var monitor: Any?
    @State private var clock = Date()

    var body: some View {
        let caps = model.caps
        let count = min(caps.macroCount, model.profile.macros.count)
        ZStack(alignment: .topLeading) {
            if let bg = model.skin?.image("macro_nr.png") { SkinImage(image: bg) }
            else { RoundedRectangle(cornerRadius: 4).fill(Skin.popBack).overlay(RoundedRectangle(cornerRadius: 4).stroke(Skin.popFrame)).frame(width: 767, height: 418) }
            Text("Macro Editor").font(Skin.font(13, .semibold)).foregroundColor(Skin.over).at(20, 12)
            SkinButton(nr: "exit_nr.png", ov: "exit_ov.png", dn: "exit_ov.png", text: "×", w: 15, h: 15) { close() }.at(735, 14)
            Text("Macro list").font(Skin.font(11)).foregroundColor(Skin.text).at(20, 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<count, id: \.self) { i in
                        row("\(i + 1). \(model.profile.macros[i].name)", selected: i == index).onTapGesture { stopRecording(); index = i }
                    }
                }
            }.frame(width: 180, height: 250).at(20, 64)
            if index < count {
                TextField("Name", text: $model.profile.macros[index].name).frame(width: 170).at(20, 324)
                Text("Key list").font(Skin.font(11)).foregroundColor(Skin.text).at(220, 44)
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.profile.macros[index].events.enumerated()), id: \.offset) { n, e in
                            row(String(format: "%3d  %@ %@", n + 1, e.press ? "↓" : "↑", HIDKey.name(e.key)), selected: false)
                            Text("        Delay \(e.delayMs) ms").font(Skin.font(10)).foregroundColor(Skin.text)
                        }
                    }
                }.frame(width: 320, height: 290).background(Skin.listBack).at(220, 64)
                VStack(alignment: .leading, spacing: 8) {
                    SkinButton(nr: recording ? "recbtn_dn.png" : "recbtn_nr.png", ov: "recbtn_dn.png", dn: "recbtn_dn.png",
                               text: recording ? "Stop record" : "Start record", w: 128, h: 30) { recording ? stopRecording() : startRecording() }
                    Text(recording ? "Recording – press keys" : "Records keys pressed while this window is focused")
                        .font(Skin.font(10)).foregroundColor(recording ? Skin.down : Skin.text).frame(width: 190, alignment: .leading)
                    Text("Insert event").font(Skin.font(11)).foregroundColor(Skin.text)
                    HStack(spacing: 4) {
                        mini("+ Left") { addClick(0xF0) }
                        mini("+ Right") { addClick(0xF1) }
                        mini("+ Middle") { addClick(0xF2) }
                    }
                    HStack(spacing: 4) {
                        mini("+ Delay 50") { if !model.profile.macros[index].events.isEmpty { model.profile.macros[index].events[model.profile.macros[index].events.count - 1].delayMs += 50 } }
                        mini("Delete last") { if !model.profile.macros[index].events.isEmpty { model.profile.macros[index].events.removeLast() } }
                    }
                    mini("Clear") { model.profile.macros[index].events.removeAll() }
                    Stepper("Specified cycle times: \(model.profile.macros[index].repeatCount)",
                            value: Binding(get: { Int(model.profile.macros[index].repeatCount) }, set: { model.profile.macros[index].repeatCount = UInt16($0) }), in: 1...65535)
                        .font(Skin.font(11)).foregroundColor(Skin.text)
                    Text("Max \(caps.macroBytes) bytes per macro, \(caps.macroCount) macros. Assign it to a button with the function picker, then Apply.")
                        .font(Skin.font(10)).foregroundColor(Skin.text).frame(width: 190, alignment: .leading)
                }
                .at(560, 64)
            }
            SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "OK", w: 92, h: 27) { model.save(); close() }.at(655, 376)
        }
        .frame(width: 767, height: 418, alignment: .topLeading)
        .onDisappear { stopRecording() }
    }

    func row(_ text: String, selected: Bool) -> some View {
        Text(text).font(Skin.font(11.5)).foregroundColor(selected ? .black : Skin.text)
            .frame(width: 170, height: 20, alignment: .leading).padding(.leading, 6)
            .background(selected ? Skin.listItem : Skin.listBack)
    }

    func mini(_ text: String, _ a: @escaping () -> Void) -> some View {
        SkinButton(nr: "dot_nr.png", ov: "dot_ov.png", dn: "dot_nr.png", text: text, w: max(56, CGFloat(text.count) * 7 + 14), h: 20, action: a)
    }

    func addClick(_ b: UInt8) { model.profile.macros[index].events += Macro.tap(b) }

    func close() { stopRecording(); model.showMacroEditor = false }

    func startRecording() {
        recording = true
        clock = Date()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { ev in
            let u = HIDKey.fromMacKeyCode(ev.keyCode)
            guard recording, u != 0, !(ev.type == .keyDown && ev.isARepeat) else { return nil }
            var press = ev.type == .keyDown
            if ev.type == .flagsChanged {   // modifier: pressed if its bit is now set
                let map: [UInt8: NSEvent.ModifierFlags] = [0xE0: .control, 0xE4: .control, 0xE1: .shift, 0xE5: .shift, 0xE2: .option, 0xE6: .option, 0xE3: .command, 0xE7: .command]
                let flags = map[u] ?? []
                press = ev.modifierFlags.contains(flags)
            }
            let ms = Int(Date().timeIntervalSince(clock) * 1000)
            clock = Date()
            var events = model.profile.macros[index].events
            if !events.isEmpty { events[events.count - 1].delayMs = max(1, min(model.caps.macroMaxDelayMs, ms)) }
            events.append(MacroEvent(key: u, press: press, delayMs: 20))
            model.profile.macros[index].events = events
            return nil
        }
    }

    func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}

// MARK: - info

struct InfoPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(Skin.popBack).overlay(RoundedRectangle(cornerRadius: 4).stroke(Skin.popFrame)).frame(width: 530, height: 360)
            Text("Device").font(Skin.font(13, .semibold)).foregroundColor(Skin.over).at(20, 12)
            ScrollView {
                Text(lines.joined(separator: "\n")).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Skin.text)
                    .textSelection(.enabled).frame(width: 470, alignment: .leading)
            }.frame(width: 490, height: 250).background(Skin.listBack).at(20, 40)
            HStack(spacing: 8) {
                if model.caps.skinProbe != nil {
                    SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "Import skin…", w: 92, h: 27) { importSkin() }
                }
                SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "Export…", w: 92, h: 27) { export() }
                SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "Reconnect", w: 92, h: 27) { model.showInfo = false; model.connect() }
                Spacer().frame(width: 60)
                SkinButton(nr: "button3_nr.png", ov: "button3_ov.png", dn: "button3_nr.png", text: "Close", w: 92, h: 27) { model.showInfo = false }
            }.at(20, 310)
        }
        .frame(width: 530, height: 360, alignment: .topLeading)
    }

    var lines: [String] {
        var l = ["Supported: " + MouseDevices.supported.map { String(format: "%@ (%04X:%04X)", $0.name, $0.vendorID, $0.productID) }.joined(separator: ", ")]
        l.append(model.skin.map { "Vendor skin: " + $0.folder.path } ?? "Vendor skin: not imported – showing the drawn look-alike.")
        if let d = model.driver { l += d.diagnostics() }
        l.append("— log —")
        l += model.logLines.suffix(40)
        return l
    }

    func importSkin() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.zip, .folder, .png]
        p.canChooseDirectories = true
        p.message = "Choose the vendor app's zip, its folder, or its skins folder"
        if p.runModal() == .OK, var url = p.url {
            if url.pathExtension.lowercased() == "png" { url = url.deletingLastPathComponent() }
            model.importSkin(from: url)
        }
    }

    func export() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "\(model.driver?.id ?? "mouse")-profile.json"
        if p.runModal() == .OK, let url = p.url { try? model.exportProfile(to: url) }
    }
}

// MARK: - colour helpers

extension Color {
    init(rgb: RGB) { self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255) }
    var rgb: RGB {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return RGB(UInt8(max(0, min(255, c.redComponent * 255))),
                   UInt8(max(0, min(255, c.greenComponent * 255))),
                   UInt8(max(0, min(255, c.blueComponent * 255))))
    }
}
