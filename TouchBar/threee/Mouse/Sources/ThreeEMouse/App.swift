import SwiftUI
import AppKit
import MouseCore

// Opened by 3£ ("Mouse…" in the menu-bar menu). 3£ owns the menu-bar icon, so this helper
// only shows a window and quits when it is closed.
@main
struct ThreeEMouseApp: App {
    @NSApplicationDelegateAdaptor(MouseAppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("3£ Mouse") {
            ContentView().environmentObject(model)
                .frame(minWidth: 820, minHeight: 600)
        }
    }
}

final class MouseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if model.detected.count > 1 {
                    Picker("", selection: Binding(get: { model.selectedID ?? "" },
                                                  set: { model.selectedID = $0; model.connect() })) {
                        ForEach(model.detected) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(width: 200)
                }
                Image(systemName: model.connected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.connected ? .green : .orange)
                Text(model.status).lineLimit(2).font(.callout)
                Spacer()
                if model.caps.extraSideSlot > 0 && model.caps.actions.contains(.key) {
                    Menu("Side button") {
                        Button("F13 (3£ Kalista kite)") { model.setSideKey(HIDKey.f13) }
                        Button("Pause") { model.setSideKey(HIDKey.pause) }
                    }
                    .frame(width: 120).disabled(!model.connected)
                }
                Button("Reconnect") { model.connect() }
                if model.driver != nil {
                    Button("Read from mouse") { model.readFromMouse() }.disabled(!model.connected)
                    Button("Apply") { model.apply() }.keyboardShortcut("s").buttonStyle(.borderedProminent)
                        .disabled(!model.connected)
                }
            }
            .padding(10)
            Divider()
            TabView {
                if model.caps.hasButtons { ButtonsView().tabItem { Label("Buttons", systemImage: "computermouse") } }
                if model.caps.hasDPI { DPIView().tabItem { Label("DPI", systemImage: "speedometer") } }
                if model.caps.hasLighting { LightingView().tabItem { Label("Lighting", systemImage: "lightbulb") } }
                if model.caps.hasPolling {
                    PerformanceView().tabItem { Label(model.caps.modes > 1 ? "Polling / Modes" : "Polling rate", systemImage: "gauge") }
                }
                if model.caps.hasMacros { MacrosView().tabItem { Label("Macros", systemImage: "keyboard") } }
                DeviceView().tabItem { Label("Device", systemImage: "info.circle") }
            }
            .padding(8)
            .id(model.selectedID ?? "none")
        }
    }
}
