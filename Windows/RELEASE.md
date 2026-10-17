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
- **3e.local:** the stable name is now http://3e.local:17833 (was phonebar.local).

Gesture handling was informed by KDE Connect's phone touchpad (speed-based acceleration and scroll direction lock); this is an independent implementation.

Includes everything from 1.0.25:

- The top volume button is the speaker-with-sound-waves icon (volume up) and the bottom one is a speaker with a single small wave (volume down). Both press the laptop's volume keys. The separate speaker icon above the slider is gone.

Includes everything from 1.0.24:

- **One link that keeps working:** the pairing link is saved, so it is the same after restarts, updates and network changes. Phone Bar now stays on and restarts itself after sleep or a network change. The tray has "Phone Bar — new link" to revoke the old link; "Stop Phone Bar" turns it off until you open the QR again.
- **phonebar.local:** the receiver answers http://phonebar.local:17833. The QR still opens the IP address; the page switches to phonebar.local automatically when the network supports it, so a bookmark or home-screen icon keeps working when the laptop's IP changes. Networks that block .local names keep using the IP link.
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
