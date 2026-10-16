3£Windows 1.0.21 fixes the tray menu.

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
