import Cocoa
import SwiftUI
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    private static let statusIcon = templateImage(named: "StatusIcon")
    private static let statusIconWarning = templateImage(named: "StatusIcon-Warning")

    private var statusBarItem: NSStatusItem!
    private var aboutWindow: NSWindow!

    private static func templateImage(named: String) -> NSImage? {
        let image = NSImage(named: named)
        image?.isTemplate = true
        return image
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #endif

        createStatusBarItem()
        requestAccessibilityPermission() {
            self.startGestures()
        }
    }

    private func startGestures() {
        SwipeManager.start()
        if !SwipeManager.isRunning {
            let item = NSMenuItem(title: "Gesture access unavailable — quit and reopen after authorizing", action: nil, keyEquivalent: "")
            item.isEnabled = false
            statusBarItem.menu?.insertItem(item, at: 0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SwipeManager.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarItem.isVisible=true
        return true
    }

    private func requestAccessibilityPermission(completion: @escaping ()->()) {
        let isAccessibilityPermissionGranted = PrivacyHelper.isProcessTrustedWithPrompt()
        os_log("Accessibility granted: %{public}d", log: OSLog(subsystem: "ris58h.Touch-Tab", category: "Gestures"), type: .info, isAccessibilityPermissionGranted ? 1 : 0)
        debugPrint("Accessibility permission", isAccessibilityPermissionGranted)
        if isAccessibilityPermissionGranted {
            completion()
        } else {
            addAccessibilityWarning()
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] timer in
                if AXIsProcessTrusted() {
                    os_log("Accessibility granted after authorization", log: OSLog(subsystem: "ris58h.Touch-Tab", category: "Gestures"), type: .info)
                    debugPrint("Accessibility permission granted")
                    removeAccessibilityWarning()
                    timer.invalidate()
                    completion()
                }
            }
        }
    }

    private func createStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = AppDelegate.statusIcon
        statusBarItem.button?.toolTip = BundleInfo.displayName()
        statusBarItem.behavior = .removalAllowed

        statusBarItem.menu = NSMenu()
        statusBarItem.menu?.addItem(
            withTitle: "Check for Updates…",
            action: #selector(AppDelegate.checkForUpdates),
            keyEquivalent: "")
        statusBarItem.menu?.addItem(
            withTitle: "About \(BundleInfo.displayName())",
            action: #selector(AppDelegate.showAbout),
            keyEquivalent: "")
        statusBarItem.menu?.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quit),
            keyEquivalent: "")
    }

    private func addAccessibilityWarning() {
        statusBarItem.button?.image = AppDelegate.statusIconWarning
        let warningDescriptionMenuItem = NSMenuItem(title: "No Accessibility Access", action: nil, keyEquivalent: "")
        warningDescriptionMenuItem.image = AppDelegate.templateImage(named: "MenuItem-Warning")
        warningDescriptionMenuItem.toolTip = "Grant access to this application in Privacy & Security settings, located in System Settings"
        warningDescriptionMenuItem.isEnabled = false
        let openPrivacyAccessibilityMenuItem = NSMenuItem(title: "Authorize...", action: #selector(openPrivacyAccessibility), keyEquivalent: "")
        statusBarItem.menu?.insertItem(warningDescriptionMenuItem, at: 0)
        statusBarItem.menu?.insertItem(openPrivacyAccessibilityMenuItem, at: 1)
        statusBarItem.menu?.insertItem(NSMenuItem.separator(), at: 2)
    }

    private func removeAccessibilityWarning() {
        statusBarItem.button?.image = AppDelegate.statusIcon
        statusBarItem.menu?.removeItem(at: 2)
        statusBarItem.menu?.removeItem(at: 1)
        statusBarItem.menu?.removeItem(at: 0)
    }

    @objc private func openPrivacyAccessibility() {
        let privacyAccessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(privacyAccessibilityURL)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }

    @objc private func checkForUpdates() {
        AppReleaseUpdates.check()
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            aboutWindow = NSWindow(contentViewController: NSHostingController(rootView: AboutView().fixedSize()))
            aboutWindow.styleMask = [.closable, .titled]
            aboutWindow.title = ""
        }
        aboutWindow.center()
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Shared repository, independent app releases. Never use /releases/latest here.
enum AppReleaseUpdates {
    static func newest(_ value: Any) -> (version: String, url: URL)? {
        guard let releases = value as? [[String: Any]] else { return nil }
        var newest: (version: String, url: URL)?
        for release in releases {
            guard release["draft"] as? Bool != true,
                  release["prerelease"] as? Bool != true,
                  let tag = release["tag_name"] as? String,
                  tag.range(of: "^touchtab-v[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
                  let assets = release["assets"] as? [[String: Any]] else { continue }
            let version = String(tag.dropFirst("touchtab-v".count))
            let expected = "https://github.com/Ezodis/3E/releases/download/\(tag)/TouchTab.zip"
            guard assets.contains(where: { ($0["name"] as? String) == "TouchTab.zip" && ($0["browser_download_url"] as? String) == expected }),
                  let url = URL(string: expected) else { continue }
            if newest == nil || version.compare(newest!.version, options: .numeric) == .orderedDescending {
                newest = (version, url)
            }
        }
        return newest
    }

    static func check() {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Ezodis/3E/releases?per_page=100")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("3E-TouchTab", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let release: (version: String, url: URL)?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
               let data = data, let json = try? JSONSerialization.jsonObject(with: data) {
                release = newest(json)
            } else { release = nil }
            DispatchQueue.main.async {
                let newer = release.map { $0.version.compare(BundleInfo.version(), options: .numeric) == .orderedDescending } ?? false
                let alert = NSAlert()
                alert.messageText = newer ? "A TouchTab update is available" : (release == nil ? "Could not check for updates" : "TouchTab is up to date")
                alert.informativeText = "Installed version: \(BundleInfo.version()). TouchTab updates come from Ezodis/3E. Downloads do not replace your running app."
                alert.addButton(withTitle: newer ? "Download" : "OK")
                if newer { alert.addButton(withTitle: "Later") }
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn, newer, let release = release {
                    NSWorkspace.shared.open(release.url)
                }
            }
        }.resume()
    }
}
