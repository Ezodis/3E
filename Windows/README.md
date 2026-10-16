# 3£Windows

One Windows tray app for three-finger dragging, Clicks keyboard mapping, PowerToys shortcuts/Workspaces, auto dark mode and dynamic wallpaper. The drag engine runs inside the app. PowerToys, Kanata and WinDynamicDesktop are managed background dependencies, with their normal tray icons hidden. Auto dark mode runs directly inside 3£Windows, using light mode from noon until 8 PM and dark mode otherwise.

## Install and export

Download [`3£Windows.ps1`](../3%C2%A3Windows.ps1) from this repository, or extract it from **3EWindows.zip** in a [`windows-v…` release](https://github.com/Ezodis/3E/releases). The ZIP preserves the exact filename despite GitHub's asset-name normalization. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\3£Windows.ps1'
```

Copy that one file to another PC to replicate the setup. It embeds the x64 and ARM64 app builds, keyboard rules, PowerToys shortcut profile, signed Clicks drivers, reconnect guard, and accent/symbol picker. No companion `.kbd`, Python scripts, ZIP or source files are required beside the installer. Installation extracts its maintained runtime files under `%ProgramFiles%\3EWindows`. Internet is required for missing .NET 10, Windows App Runtime 1.8, PowerToys and WinDynamicDesktop. First setup needs administrator approval and a Windows restart for the modifier swap. Corporate policy may restrict elevation or input filters.

Windows 10 1809+ and Windows 11 are supported by the app framework; individual current PowerToys releases may require a newer Windows build. Both x64 and ARM64 binaries build here; ARM64 has not been physically tested. Clicks Interception requires x64 Windows, and three-finger drag requires a Precision Touchpad. The microphone key is unchanged because current Clicks firmware supplies no Windows-visible event.

The main app installs under `%ProgramFiles%\3EWindows`, with preferences under `%LOCALAPPDATA%\3EWindows`. The installer is retained as `%ProgramFiles%\3EWindows\3£Windows.ps1`. Generated internal keyboard files remain under `Keyboard`; they are implementation files managed by the app, not a separately named PowerKeyboard product.

## Controls and migration

**iPhone trackpad and MIDI studio:** connect the phone and laptop to the same trusted Wi-Fi, left-click the tray icon and scan its QR code using iPhone Camera. The full-viewport trackpad has Apps and Media controls. Tap to click; two-finger tap right-clicks; two fingers scroll; three fingers drag. Tap once, then touch again within 500 ms and move to drag. The second touch presses immediately; a 120 ms contact-break grace period helps sustain a drag. Quick double taps still double-click. Four fingers left/right change virtual desktops, up opens Task View, and down shows the desktop. Hold Apps, slide left/right through the Alt+Tab chooser, then lift to select. Tap Media to play/pause, swipe for previous/next, or hold for the two-deck and eight-track MIDI studio. There is no separate Drag button. Settings offers 0.5×–20× pointer speed. The shared Windows/macOS interface, MIDI mapping table and Ableton setup are documented in [Phone Control](../Shared/PhoneControl/README.md).

The page releases input when hidden and reconnects automatically on return. Brief failures retry with bounded backoff; explicit Pause stays paused. Expired links ask for a fresh QR code. Swipe scrolling follows the reversed direction introduced in 1.0.12.

**Apple Watch (including SE 2 / watchOS 26):** email or message the normal pairing URL to yourself, open the message on the watch and tap it. No special watch URL or sharing button is needed: the page automatically chooses the compact layout and HTTP transport. Older links with `?watch=1` remain supported. Use the full web page view if Reader hides the controls. The watch must reach the laptop on the same local network. Close/background the phone page or choose **Settings → Pause connection** before switching devices; only one device controls the cursor at a time. Sleep/wake resumes automatically. Choose **Connect** after an explicit pause. Send a fresh link after restarting the receiver or changing networks. Delivering a message/email may need internet; the trackpad connection itself stays local.

The watch layout keeps the Apps, Media and Scroll buttons floating over a full-viewport pad; Settings contains speed and arrow controls for viewers that consume swipes. Tapping the pad still clicks in viewers that expose only click events. It uses authenticated, ordered HTTP batches because watchOS WebKit disables WebSockets by default. Watch sleep/disconnect releases dragging after six seconds (checked every 1.5 seconds). Desktop WebKit/Chromium tests cover the same URL, tiny screens, both orientations, HTTP controls, switching devices, broken sockets and sleep/wake without reload; actual SE 2 hardware compatibility still needs testing.

**Single-contact controls:** enable this in Settings for tongue or one-contact operation. Swipe to move, tap to click, hold still for 800 ms to right-click, and use Scroll/Move for scrolling, and double-tap then move for dragging. Taps allow up to 750 ms and slightly more movement; double-tap dragging remains available. Both portrait and landscape work, and rotation releases any held drag. This mode is saved on the device and does not mirror the desktop screen.

Movement is sent from touch events with an 8 ms minimum interval; the animation-frame callback drains residual motion. High-speed movement fits one bounded packet (up to 8000 units per axis), avoiding a queue of 1000-unit chunks. Watch HTTP sends immediately when idle and combines adjacent motion while a request is in flight, preserving click/button ordering. Heartbeat replies detect stalled sockets. The same page can reclaim its own sleeping controller immediately, while other devices remain excluded. Real device and Wi-Fi latency has not been measured.

**Full screen:** the pad always fills the available browser viewport. Settings → Full screen requests the Fullscreen API where supported. On iPhone, use Safari Share → Add to Home Screen → Open as Web App for a standalone view without normal Safari bars. Apple Watch browser controls are controlled by watchOS and cannot be removed by the page. A Home Screen shortcut still contains a session-specific URL, so reopen a fresh pairing link after restarting the receiver.

The receiver is off at every app startup and starts only when requested. No local network, network changes, port conflicts or firewall errors affect the other components. Network loss stops the session; start again after reconnecting. Closing the popup keeps the session running; **Stop trackpad** in the popup or **Stop iPhone trackpad** in the right-click menu ends the session. Quit also stops it. A disconnected or suspended phone releases a held drag, with a six-second heartbeat timeout for silent disconnects. Each new session generates a fresh 192-bit pairing secret. Only one authenticated phone can control the cursor. The service binds TCP port 17833 to a local Wi-Fi/Ethernet IPv4 address and temporarily permits only the local subnet through Windows Firewall; it does not enable router forwarding. HTTP is local and unencrypted, so use a trusted LAN. Guest networks that isolate devices may block connections. An iPhone Personal Hotspot may also work if the laptop joins it and the devices can reach each other locally.

The source for this feature is MIT-licensed alongside the app; QR codes are generated locally with the MIT-licensed QRCoder library. Run `dotnet run --project Windows/PhoneTrackpadTests`, `node Windows/PhoneTrackpadTests/gestures.test.cjs` and `node Windows/PhoneTrackpadTests/watch.test.cjs` for network-loss/authentication, touch gestures and watch handoff tests using simulated input. No actual iPhone, Apple Watch or ARM64 hardware is emulated by these checks.

Left-click **3£Windows** to show the iPhone QR popup. Right-click for **iPhone / Watch trackpad — show QR**, drag settings, PowerToys settings, keyboard controls, theme controls, wallpaper, component toggles, update checks and the portable installer. All controls previously available from left-click remain available on right-click. Disabling a component persists across restarts. **Quit** stops the app and its managed engines. **Show wallpaper controls** deliberately reveals WinDynamicDesktop's own controls; this can temporarily reveal its icon. Normal operation has one suite icon.

**Rotate SSMS themes** chooses a different installed SSMS 22 theme at app startup, noon and 8 PM. Light palettes are used during the day and dark palettes at night, matching the Windows schedule and manual mode overrides. Themes are discovered from SSMS's own registrations, including Bubblegum, Cool Breeze, Icy Mint, Mango Paradise, Silky Pink, Sunny Day, Cool Slate, Juicy Plum, Moonlight Glow, Mystical Forest and Spicy Red when installed. The previous theme is excluded from each new choice. **Rotate SSMS theme now** picks another matching palette immediately. Existing profiles are discovered automatically, including profiles first created after setup. Other settings and JSON comments are preserved; the original file is backed up before the first change. Disable the toggle to manage SSMS's theme yourself. Older SSMS versions are left unchanged.

Setup removes duplicate Edy input startup tasks and their registry autoruns, preserves drag/wallpaper preferences, and installs one `3£Windows` sign-in task plus a short resume recovery task. A separate scheduled Kiro theme action preserves the existing noon/8 PM theme behavior. PowerToys Light Switch is disabled to avoid competing with the integrated auto dark engine. Existing keyboard device IDs are discovered on each destination PC, never embedded from the exporting PC.

Running the same version launches the suite directly. Running a newer portable file updates the app and previously configured Clicks components. `-AppOnly` performs that update while retaining input preferences and the keyboard enable state; the built-in updater uses it. `-Install` explicitly runs full setup. `-RepairKeyboard` configures or restores the Clicks mapping after pairing. `-KeyboardOnly` sets only the left Alt/Ctrl scan-code swap. `-Down` removes the suite and restores saved input settings while retaining third-party applications/runtimes. A legacy class-wide Interception filter must be removed and Windows restarted before Clicks-only setup; the new installer never attaches its filter to the keyboard or mouse class.

## Clicks keys and hold menus

Use the keyboard's Android mode for Windows. Mapping applies only to verified Clicks Power Keyboard devices. Command acts as Ctrl; the labeled Ctrl key sends right Alt, avoiding the existing left-Alt shortcut remaps; the red Clicks key remains Tab; the six-dot key opens Windows. Double-tap Command within 350 ms for Windows dictation. Tap Command or Shift to apply it to the next key within five seconds; sequential Command and Shift taps combine. Holding either modifier keeps normal modifier behavior.

Hold a letter or number for 650 ms, release it, then press 1–9 to choose. Letter menus offer accents, including uppercase variants. Esc cancels; the menu expires after six seconds. Ctrl/Alt/Windows shortcuts and other keyboards do not activate the picker. Selection replaces the original character without using the clipboard or recording typed text.

| Hold | Choices |
| --- | --- |
| 0 | 🙂 😂 ❤️ 👍 🙏 🎉 🔥 ✅ 👀 |
| 1 | $ € £ ¥ ¢ ₹ ₩ ₽ ₿ |
| 2 | ± × ÷ ≈ ≠ ≤ ≥ ∞ √ |
| 3 | ✓ ✗ ★ ♥ ☀ ☂ ☕ ⌘ ⚡ |
| 4 | ← → ↑ ↓ ↔ ↕ ↗ ↘ ⇒ |
| 5 | ¿ ¡ … — – • · « » |
| 6 | Square, curly and angle brackets |
| 7 | © ® ™ ° § ¶ † ✓ ✗ |
| 8 / 9 | Superscript / subscript digits |

For example, hold **1**, release, then press **2** to type **€**. The reconnect guard prevents the legacy driver from exhausting its keyboard slots after repeated Bluetooth reconnects. The picker stops with the keyboard component; reconnect protection stays running while its device driver is installed.

## Updates and releases

The app checks daily without pop-up notifications and displays available updates in its menu. **Check for updates** examines only stable `windows-v…` releases of `Ezodis/3E`; it cannot select a Mac release. Installing an update requires an explicit click, a valid SHA-256 match against that release's `SHA256SUMS.txt`, and Windows administrator approval. Failed/offline checks wait until the next daily attempt; the menu can retry immediately.

The unsigned app is built from maintained source and includes the upstream drag MIT license. Microsoft installer Authenticode signatures are checked; .NET is also checked against Microsoft's SHA-512 metadata. WinDynamicDesktop's unsigned installer is checked against its official GitHub asset's SHA-256 digest, and Kanata against its published checksums. Windows may request approval for an unsigned downloaded script/app. A published release is immutable; increment [`version.json`](version.json) before publishing another version.

## Build

Install the .NET 10 SDK on x64 Windows, then run `./Windows/build.ps1` from the repository root. It builds both app architectures and the keyboard helpers, runs offline modifier/dictation, Unicode picker and device-routing tests, runs the app's schedule/update tests, parses the assembled installer, and generates the root script plus release assets under `build/windows/release`. The keyboard build downloads checksum-pinned Zig 0.13.0 if necessary; `THREEE_ZIG` may point to an existing compiler. Zig and the test harnesses are build-only dependencies. Vendor hashes and licenses are maintained under `Keyboard`. Windows PowerShell 5.1 compatibility is preserved by a UTF-8 BOM. ARM64 is cross-compiled; keyboard helpers and self-tests run on x64.

The [Windows workflow](../.github/workflows/windows-releases.yml) rebuilds and publishes a new version after successful validation. It does not mark Windows as the global latest release or interfere with the existing Mac edition channels. The generated root script is committed for direct copying; release assets are regenerated from the same source/template.

The drag source in [`DragEngine`](DragEngine/) is adapted from [ClementGre/ThreeFingerDragOnWindows](https://github.com/ClementGre/ThreeFingerDragOnWindows), retaining the [MIT license](DragEngine/LICENSE). Device-specific keyboard translation uses [Kanata](https://github.com/jtroo/kanata) and [Interception](https://github.com/oblitum/Interception). Other dependencies retain their own licenses and official update/install channels.
