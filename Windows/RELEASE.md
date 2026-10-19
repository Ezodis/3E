3£Windows 1.0.38 uses the 3£ logo everywhere.

- **No more three-finger-drag icon:** the app's icon (taskbar, Alt+Tab, Task Manager, Startup apps, notifications), the settings window, its title bar and all app tiles now show the 3£ logo, the same one the Mac app uses.
- **Clicks accent picker** tray icon is the 3£ logo instead of a generic Windows "info" icon.
- The drag engine's upstream credit in Other Settings keeps its name and links, with a neutral info icon.

Includes everything from 1.0.37:

3£Windows 1.0.37 keeps the Phone Bar link the same on every network.

- **One permanent link:** the QR now always shows `http://3e-win.local:17833/#…` instead of the PC's IP address. The saved secret and the `3e-win.local` name stay the same, so the link on your iPhone, Home Screen or Apple Watch keeps working when the IP changes.
- **Follows IP changes by itself:** when DHCP, a different Wi-Fi or a hotspot gives the PC a new address, Phone Bar rebinds to it and re-announces `3e-win.local` with the new IP. If Wi-Fi drops, it pauses and comes back on its own when a network returns. No need to turn it off and on or rescan.
- The Mac receiver (`3e-mac.local`) gets the same automatic rebinding.

Includes everything from 1.0.36:

3£Windows 1.0.36 adds a full restart.

- **Restart** (was "Restart input engines") quits and relaunches the whole suite: the tray app, three-finger drag, the Clicks keyboard engine, PowerToys, the wallpaper app and Phone Bar all start fresh. No administrator prompt; the Phone Bar link is kept.

Includes everything from 1.0.35:

3£Windows 1.0.35 shortens the Clicks keyboard row.

- **Clicks keyboard:** the "— running" / "— stopped" text is gone; the check mark now shows it is running. Click an unchecked row to start it, a checked row to stop it.

Includes everything from 1.0.34:

3£Windows 1.0.34 gives the tray menu real icons and one row per feature.

- **Real icons:** rows with settings show a Windows sliders icon at the right edge (Segoe Fluent Icons). Click the row to toggle; click the icon for settings.
- **Phone Bar is one row, at the top:** click to turn it on or off; its icon makes a new link (after confirming, since the old link stops working). Left-clicking the tray icon still shows the QR.
- **Rotate themes:** one row replaces "Rotate SSMS themes" and "Rotate SSMS theme now". Click to switch rotation on or off; the repeat icon rotates now. Rotation now covers SSMS and every installed VS Code–style editor (Kiro, VS Code, Cursor, Windsurf, VSCodium), choosing from each one's installed light or dark themes. The old separate Kiro theme task is removed.

Includes everything from 1.0.33:

3£Windows 1.0.33 simplifies the tray menu further.

- **Simpler settings icon:** the ⚙ is now a quiet ⋯ at the right edge of Three-finger drag, PowerToys shortcuts and Dynamic wallpaper. Click the row to toggle; click the ⋯ for settings.
- **No "Check for updates…" item** while "Install updates automatically" is on. Turn automatic updates off and the manual check comes back.

Includes everything from 1.0.32:

3£Windows 1.0.32 tidies the tray menu.

- **Gear icons:** Three-finger drag, PowerToys shortcuts and Dynamic wallpaper each have a ⚙ at the right edge. Click the row to switch it on or off; click the ⚙ to open its settings. The separate "Drag settings…", "PowerToys settings…" and "Show wallpaper controls…" items are gone.
- **Phone Bar is one checkbox:** "Phone Bar" is checked while it runs; click it to start or stop. "Show QR…" is removed because left-clicking the tray icon already shows the QR.
- **Dynamic wallpaper** now heads the theme section.
- **Browser title:** the Phone Bar tab and home-screen name is "3£ -win" on Windows ("3£ -mac" on the Mac receiver), so the two are easy to tell apart.

Includes everything from 1.0.31:

3£Windows 1.0.31 gives the Windows Phone Bar a unique local-network address.

- **Windows phone link:** scan or open `http://3e-win.local:17833`. The Mac receiver uses `3e-mac.local`, so both receivers can run on the same network without sending a QR link to the other computer.

3£Windows 1.0.30 makes Media's previous/next swipe work even when YouTube is in the background.

- **Skips reach an unfocused YouTube:** when Chrome's media session refuses the skip (common when its window isn't focused), 3£Windows sends the hardware Next/Previous media key, which Chrome and Edge handle in the background. If Previous still can't go back, the current video restarts from the beginning.
- **Diagnostics:** each skip is logged to `%LOCALAPPDATA%\3EWindows\media.log` (app, whether skip was available, which route worked).

3£Windows 1.0.29 makes Media's previous/next swipe reliable.

- **Curved thumb swipes skip:** a swipe that starts slightly up or down no longer turns into the volume control; the skip is decided from where your finger ends up. The volume opens only for a clearly vertical swipe.
- **Quick repeated skips are not lost:** swipes made while the music app is still answering the previous command are queued and delivered in order (play/pause double-taps are still ignored so playback never toggles twice).
- **Slow starts skip instead of opening the MIDI controls**, and a touch the browser never finished no longer swallows the next swipe.

Includes everything from 1.0.28:

- **Tap-hold-drag never clicks first:** like a laptop touchpad with tap-and-drag, a tap's click waits 0.3 s for a possible second touch. Tap, touch again and hold, then move is now a pure drag: Task View no longer opens the window before you can drag it, and menus stay open. A quick double tap is still a double-click, and moving or touching elsewhere sends the waiting click immediately, at the spot you tapped.
- **Small movements register immediately:** the pointer now moves by exact pixels, so Windows' "Enhance pointer precision" no longer shrinks slow, small phone movements to nothing and then jumps. After a tap, a new movement starts after 6 px instead of 14 px. Pointer acceleration is gentler at slow speeds; adjust Pointer speed in Settings if the overall speed feels different.

Includes everything from 1.0.27:

- **Automatic updates:** 3£Windows checks for a new release every 10 minutes and installs it silently once the computer has been idle for 90 seconds, so it never restarts while you are using it. No prompt is needed because the app already runs with administrator rights; the installer is still verified against the release's SHA-256 checksum.
- If a release fails to install twice, it is left for a manual "Check for updates".
- Turn it off with "Install updates automatically" in the tray menu.

Includes everything from 1.0.26:

- **Two-finger swipe for Back/Forward:** a quick sideways two-finger swipe goes back (fingers right) or forward (fingers left) in Chrome, Edge, Firefox and File Explorer. A slower sideways slide scrolls horizontally instead.
- **Smoother scrolling:** two-finger scrolls lock to their direction (small drift is ignored) and keep gliding after you lift; touching the pad stops the glide. The finger left behind after a two-finger gesture no longer jumps the pointer.
- **Pinch to zoom** (Ctrl + wheel on Windows).
- **Pointer acceleration:** slow movements are precise and quick flicks cross the screen, like a laptop trackpad (switch it off in Settings for the old linear feel).
- **No more hold-to-right-click:** holding still never clicks. Use a two-finger tap to right-click.
- **3e-win.local:** the stable Windows name is now http://3e-win.local:17833. The Mac receiver uses `3e-mac.local`, so both can run on the same network without QR links reaching the wrong computer.

Gesture handling was informed by KDE Connect's phone touchpad (speed-based acceleration and scroll direction lock); this is an independent implementation.

Includes everything from 1.0.25:

- The top volume button is the speaker-with-sound-waves icon (volume up) and the bottom one is a speaker with a single small wave (volume down). Both press the laptop's volume keys. The separate speaker icon above the slider is gone.

Includes everything from 1.0.24:

- **One link that keeps working:** the pairing link is saved, so it is the same after restarts, updates and network changes. Phone Bar now stays on and restarts itself after sleep or a network change. The tray has "Phone Bar — new link" to revoke the old link; "Stop Phone Bar" turns it off until you open the QR again.
- **phonebar.local:** the receiver answered http://phonebar.local:17833. The QR still opened the IP address; the page switched to phonebar.local automatically when the network supported it, so a bookmark or home-screen icon kept working when the laptop's IP changed. Networks that blocked .local names kept using the IP link.
- **Double-tap-hold-drag fixed:** holding still now measures how far the finger actually moved, not the sum of tiny jitters, which made the drag almost impossible to arm on a real phone. The drag starts once the finger moves 6 px from where it rested.
- **Volume:** the slider follows your finger directly (iPhone handled the old hidden vertical slider badly), and new ▲/▼ buttons press the laptop's own volume keys, with Windows' volume flyout.

Includes everything from 1.0.23:

- **No more accidental presses:** moving straight after a tap is always a plain pointer move. It never presses the button, so open menus stay open and Task View no longer picks a window while you move.
- **Double-tap-hold-drag:** tap, touch again within 350 ms, hold still for a moment (the pad shows "Drag ready"), then move to drag. Lifting without moving cancels without clicking. A quick double tap is still a double-click.
- **Apps swipe down:** closes the all-windows view if it is open; otherwise shows the desktop, and swiping down again brings the windows back.

Includes everything from 1.0.22:

- **Swipe Apps up** to show all windows (Windows Task View; Mac Mission Control).
- **Swipe Apps down** to show the desktop.
- Left/right swipes, hold for the app switcher and tap for the previous app are unchanged.

Includes everything from 1.0.21:

- **Tray menu items work again:** the right-click menu is shown as a native popup, which runs each item's command and never its click handler. Every hub item (Check for updates, Stop Phone Bar, theme and keyboard toggles, Restart input engines, Quit…) was wired to the click handler, so clicking did nothing. Items now use commands, and toggles update their own check state.
- **Update dialogs come to the front:** "Check for updates" results and the install prompt open in the foreground instead of behind other windows.

Includes everything from 1.0.20:

- **No more stutter:** heartbeat replies are a few bytes and carry laptop state only when it changes, so the phone no longer rebuilds dock artwork every second during use.
- **Responsive first touch:** a touch made while the page is waking or reconnecting is kept and delivered once connected instead of being dropped, and a touch after a pause sends an immediate wake packet.
- **Laptop side:** while Phone Bar runs, the app opts out of Windows background power throttling and sets the active power plan's Wi-Fi adapter power saving to Maximum Performance. The previous values are saved and restored when Phone Bar stops, or on the next start after a crash.
- **Tap-then-drag fixed:** tap, then touch and move (or hold) now drags instead of double-clicking. Windows previously read the second press as a double-click, so files opened, title bars maximised and text selected whole words. The press now starts just outside Windows' double-click area (a few pixels), and a quick double tap sends a true double-click. macOS starts the drag with a fresh click count.
- **New dock layout:** ⌘ Shortcuts in the left corner, Apps centred, Media on the right; the phone's scroll button is removed. Press ⌘ and slide onto a shortcut, then release to send it, or tap ⌘ to pick from the palette. Apple Watch keeps its compact row.
- **One-contact controls always on:** the Settings toggle is gone; hold still to right-click, longer second-tap window and generous tap tolerance now always apply.
- **⌘ Shortcuts:** ⌘C/V/X/A, ⌘Z, ⇧⌘Z (Ctrl+Y), ⌘T, ⇧⌘T, ⌘W, ⌘N, ⌘F, ⌘S, ⌘R (F5), ⌘Space (Win+S), ⌘Q (Alt+F4), ⇧⌘3 (Win+PrtSc), ⇧⌘4 (Win+Shift+S) and ⇧⌘5 (Win+Shift+R). macOS hosts send the real ⌘ shortcuts. The protocol carries only a fixed palette id, never arbitrary keys.
- Includes the Phone Bar work from 1.0.10–1.0.19: MIDI surface, media source tracking, Apps/Media swipes, output volume swipe and the borderless layout.

Download **3EWindows.zip** and extract **3£Windows.ps1**. Run it to install or update; existing keyboard, touchpad and PowerToys preferences are preserved.

Validation includes receiver authentication, heartbeat and shortcut-range tests, shared gesture/dock/watch tests (including wake buffering and repaint suppression), the Chromium browser flow, compiled app self-tests and single-file installer verification. Real iPhone/Watch radio latency and ARM64 hardware are not measured by these automated checks.
