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

Left-click **3£Windows** to open a compact component chooser: drag settings, PowerToys settings, keyboard controls, theme controls and wallpaper. Select the component you want to configure. Right-click, or choose **All controls**, for component toggles, light/dark overrides, update checks and the portable installer. Disabling a component persists across restarts. **Quit** stops the app and its managed engines. **Show wallpaper controls** deliberately reveals WinDynamicDesktop's own controls; this can temporarily reveal its icon. Normal operation has one suite icon.

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
| 3 | ✓ ✗ ★ ♥ ☀ ☂ ☕ ⌘ ⌀ |
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
