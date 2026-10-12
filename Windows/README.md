# 3£Windows

One Windows tray app for three-finger dragging, Clicks keyboard mapping, PowerToys shortcuts/Workspaces, auto dark mode and dynamic wallpaper. The drag engine runs inside the app. PowerToys, Kanata and WinDynamicDesktop are managed background dependencies, with their normal tray icons hidden. Auto dark mode runs directly inside 3£Windows, using light mode from noon until 8 PM and dark mode otherwise.

## Install and export

Download [`3£Windows.ps1`](../3%C2%A3Windows.ps1) from this repository, or extract it from **3EWindows.zip** in a [`windows-v…` release](https://github.com/Ezodis/3E/releases). The ZIP preserves the exact filename despite GitHub's asset-name normalization. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\3£Windows.ps1'
```

Copy that one file to another PC to replicate the setup. It embeds the x64 and ARM64 app builds, the keyboard rules, the PowerToys shortcut profile and setup logic. No companion `.kbd`, ZIP or source files are required beside the installer. Internet is required for missing .NET 10, Windows App Runtime 1.8, PowerToys, WinDynamicDesktop and Clicks/Interception dependencies, which come from their official publishers. First setup needs administrator approval and a Windows restart for the keyboard driver/modifier swap. Corporate policy may restrict elevation or input filters.

Windows 10 1809+ and Windows 11 are supported by the app framework; individual current PowerToys releases may require a newer Windows build. Both x64 and ARM64 binaries build here; ARM64 has not been physically tested. Clicks Interception requires x64 Windows, and three-finger drag requires a Precision Touchpad. The microphone key is unchanged because current Clicks firmware supplies no Windows-visible event.

The main app installs under `%ProgramFiles%\3EWindows`, with preferences under `%LOCALAPPDATA%\3EWindows`. The installer is retained as `%ProgramFiles%\3EWindows\3£Windows.ps1`. Generated internal keyboard files remain under `Keyboard`; they are implementation files managed by the app, not a separately named PowerKeyboard product.

## Controls and migration

Right-click **3£Windows** for drag settings, component toggles, light/dark overrides, update checks and the portable installer. Disabling a component persists across restarts. **Quit** stops the app and its managed engines. **Show wallpaper controls** deliberately reveals WinDynamicDesktop's own controls; this can temporarily reveal its icon. Normal operation has one suite icon.

**SSMS 22 follows light/dark theme** keeps SSMS's supported `environment.visualExperience.colorTheme` preference set to `system`. It follows Windows at noon/8 PM and manual light/dark overrides. Existing SSMS 22 profiles are discovered automatically, including profiles first created after setup. Other settings and JSON comments are preserved; the original file is backed up before the first change. Disable the menu toggle to manage SSMS's theme yourself. Older SSMS versions are left unchanged.

Setup removes duplicate Edy input startup tasks and their registry autoruns, preserves drag/wallpaper preferences, and installs one `3£Windows` sign-in task plus a short resume recovery task. A separate scheduled Kiro theme action preserves the existing noon/8 PM theme behavior. PowerToys Light Switch is disabled to avoid competing with the integrated auto dark engine. Existing keyboard device IDs are discovered on each destination PC, never embedded from the exporting PC.

`-AppOnly` refreshes the application and startup integration while retaining input preferences; the built-in updater uses it. `-KeyboardOnly` sets only the left Alt/Ctrl scan-code swap. `-Down` removes the suite and restores saved input settings while retaining third-party applications/runtimes. The migration retains an existing Interception installation, and teardown removes its keyboard filter. It does not broadly reset Explorer, mouse or clipboard preferences.

## Updates and releases

The app checks daily without pop-up notifications and displays available updates in its menu. **Check for updates** examines only stable `windows-v…` releases of `Ezodis/3E`; it cannot select a Mac release. Installing an update requires an explicit click, a valid SHA-256 match against that release's `SHA256SUMS.txt`, and Windows administrator approval. Failed/offline checks wait until the next daily attempt; the menu can retry immediately.

The unsigned app is built from maintained source and includes the upstream drag MIT license. Microsoft installer Authenticode signatures are checked; .NET is also checked against Microsoft's SHA-512 metadata. WinDynamicDesktop's unsigned installer is checked against its official GitHub asset's SHA-256 digest, and Kanata against its published checksums. Windows may request approval for an unsigned downloaded script/app. A published release is immutable; increment [`version.json`](version.json) before publishing another version.

## Build

Install the .NET 10 SDK on Windows, then run `./Windows/build.ps1` from the repository root. It builds both architectures, runs compiled tests for schedule boundaries and update-channel isolation, parses the assembled PowerShell installer, and generates the root installer plus release assets under `build/windows/release`. Windows PowerShell 5.1 compatibility is preserved by a UTF-8 BOM. ARM64 is cross-compiled; the release self-test runs on x64.

The [Windows workflow](../.github/workflows/windows-releases.yml) rebuilds and publishes a new version after successful validation. It does not mark Windows as the global latest release or interfere with the existing Mac edition channels. The generated root script is committed for direct copying; release assets are regenerated from the same source/template.

The drag source in [`DragEngine`](DragEngine/) is adapted from [ClementGre/ThreeFingerDragOnWindows](https://github.com/ClementGre/ThreeFingerDragOnWindows), retaining the [MIT license](DragEngine/LICENSE). Device-specific keyboard translation uses [Kanata](https://github.com/jtroo/kanata) and [Interception](https://github.com/oblitum/Interception). Other dependencies retain their own licenses and official update/install channels.
