3£Windows combines three-finger dragging, Clicks keyboard mapping, PowerToys shortcuts and Workspaces, automatic light/dark mode, and dynamic wallpaper behind one normal tray icon.

Download **3EWindows.zip**, extract **3£Windows.ps1**, then run it with Windows PowerShell. The ZIP preserves the pound sign in the installer filename, which GitHub changes for loose release assets. Copy the extracted script alone to export the setup. The app, both architecture payloads and keyboard rules are embedded in that single file. Missing third-party applications and Microsoft runtimes download from their official sources; installation requires internet and administrator approval. Restart Windows after first installation to activate the keyboard filter and left Alt/Ctrl swap.

Windows x64 and ARM64 are included. Clicks Interception support requires x64; dragging requires a Precision Touchpad. Other input devices keep their normal mapping. The Clicks microphone button still requires firmware that reports a Windows-visible key event.

Right-click the 3£Windows icon for controls and **Check for updates**. Windows updates select only stable `windows-v…` releases, verify the published SHA-256 checksum, request approval before installation, and preserve input preferences. Daily background checks remain quiet until an update is shown in the menu.

Existing Edy input startup tasks migrate to the new app. Existing drag and wallpaper preferences are preserved. PowerToys and WinDynamicDesktop run as background dependencies with their icons hidden; explicitly choosing **Show wallpaper controls** temporarily reveals WinDynamicDesktop's own controls. PowerToys, wallpaper and keyboard engine binaries remain separate processes.

Use `-AppOnly` to refresh the app; `-KeyboardOnly` to set the left Alt/Ctrl swap; `-Down` to remove the suite and restore saved input preferences. `-Down` retains third-party applications and runtimes.
