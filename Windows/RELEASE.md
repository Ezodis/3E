3£Windows 1.0.20 makes the phone trackpad smoother and more responsive, and adds a shortcuts button to the dock.

- **No more stutter:** heartbeat replies are a few bytes and carry laptop state only when it changes, so the phone no longer rebuilds dock artwork every second during use.
- **Responsive first touch:** a touch made while the page is waking or reconnecting is kept and delivered once connected instead of being dropped, and a touch after a pause sends an immediate wake packet.
- **Laptop side:** while Phone Bar runs, the app opts out of Windows background power throttling and sets the active power plan's Wi-Fi adapter power saving to Maximum Performance. The previous values are saved and restored when Phone Bar stops, or on the next start after a crash.
- **Tap-then-drag fixed:** tap, then touch and move (or hold) now drags instead of double-clicking. Windows previously read the second press as a double-click, so files opened, title bars maximised and text selected whole words. The press now starts just outside Windows' double-click area (a few pixels), and a quick double tap sends a true double-click. macOS starts the drag with a fresh click count.
- **New dock layout:** ⌘ Shortcuts in the left corner, Apps centred, Media on the right. Apple Watch keeps its compact row.
- **⌘ Shortcuts:** ⌘C/V/X/A, ⌘Z, ⇧⌘Z (Ctrl+Y), ⌘T, ⇧⌘T, ⌘W, ⌘N, ⌘F, ⌘S, ⌘R (F5), ⌘Space (Win+S), ⌘Q (Alt+F4), ⇧⌘3 (Win+PrtSc), ⇧⌘4 (Win+Shift+S) and ⇧⌘5 (Win+Shift+R). macOS hosts send the real ⌘ shortcuts. The protocol carries only a fixed palette id, never arbitrary keys.
- Includes the Phone Bar work from 1.0.10–1.0.19: MIDI surface, media source tracking, Apps/Media swipes, output volume swipe and the borderless layout.

Download **3EWindows.zip** and extract **3£Windows.ps1**. Run it to install or update; existing keyboard, touchpad and PowerToys preferences are preserved.

Validation includes receiver authentication, heartbeat and shortcut-range tests, shared gesture/dock/watch tests (including wake buffering and repaint suppression), the Chromium browser flow, compiled app self-tests and single-file installer verification. Real iPhone/Watch radio latency and ARM64 hardware are not measured by these automated checks.
