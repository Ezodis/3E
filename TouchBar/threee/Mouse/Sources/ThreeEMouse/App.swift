import SwiftUI
import AppKit
import MouseCore

// Opened by 3£ ("Mouse…" in the menu-bar menu). 3£ owns the menu-bar icon, so this helper only
// shows the vendor-style window and quits when it is closed.
@main
struct ThreeEMouseApp: App {
    @NSApplicationDelegateAdaptor(MouseAppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("3£ Mouse") {
            VendorWindow().environmentObject(model)
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class MouseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Borderless look like the vendor window: no traffic lights; drag by the top strip.
        DispatchQueue.main.async {
            for w in NSApp.windows {
                for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.backgroundColor = .black
                w.isMovableByWindowBackground = false
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
