import SwiftUI
import AppKit
import PC205Core

// Opened by 3£ ("Mouse (PC205)…" in the menu-bar menu). 3£ owns the menu-bar icon,
// so this helper only shows a window and quits when it is closed.
@main
struct ThreeEMouseApp: App {
    @NSApplicationDelegateAdaptor(MouseAppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("3£ Mouse – PC205") {
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

extension AppModel {
    func setSideKey(_ usage: UInt8) {
        for m in 0..<PC205.modes { profile.buttons[m][Profile.likelyExtraSideSlot - 1] = .keyPress(usage) }
        apply(.matrix)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: model.connected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.connected ? .green : .orange)
                Text(model.status).lineLimit(2).font(.callout)
                Spacer()
                Menu("Side button") {
                    Button("F13 (3£ Kalista kite)") { model.setSideKey(HIDKey.f13) }
                    Button("Pause") { model.setSideKey(HIDKey.pause) }
                }
                .frame(width: 120).disabled(!model.connected)
                Button("Reconnect") { model.connect() }
                Button("Read from mouse") { model.readFromMouse() }.disabled(!model.connected)
                Button("Apply") { model.apply() }.keyboardShortcut("s").buttonStyle(.borderedProminent)
                    .disabled(!model.connected)
            }
            .padding(10)
            Divider()
            TabView {
                ButtonsView().tabItem { Label("Buttons", systemImage: "computermouse") }
                DPIView().tabItem { Label("DPI", systemImage: "speedometer") }
                LightingView().tabItem { Label("Lighting", systemImage: "lightbulb") }
                PerformanceView().tabItem { Label("Polling / Modes", systemImage: "gauge") }
                MacrosView().tabItem { Label("Macros", systemImage: "keyboard") }
                DeviceView().tabItem { Label("Device", systemImage: "info.circle") }
            }
            .padding(8)
        }
    }
}
