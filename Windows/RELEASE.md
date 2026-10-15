3£Windows 1.0.9 adds an optional iPhone trackpad with a compact QR popup. Left-click the tray icon, scan with iPhone Camera, and open the link in Safari on the same trusted Wi-Fi.

- One finger moves or taps, two fingers scroll or right-click, and three fingers drag. A Drag button also supports dragging with one finger.
- Right-click retains all existing controls and adds the QR and stop-trackpad options.
- The receiver starts only when requested. Closing the popup keeps the session connected; stopping it or quitting closes the receiver. Disconnects release a held drag, and network loss leaves the other suite components running.
- Pairing uses a new secret for each session and allows one authenticated phone. QR codes are generated locally. The connection uses local, unencrypted HTTP, so use a trusted network.
- The keyboard mappings, accents, and symbol menus from 1.0.8, including hold 3 then 9 for ⚡, are preserved.

Download **3EWindows.zip** and extract **3£Windows.ps1**. The single script contains the app, custom keyboard components, trackpad resources, and their license notices. Run it to install or update.

Validation includes picker and Unicode checks, modifier/dictation/mapping cases, simulated device routing, compiled app self-tests, single-file installer verification, receiver authentication/disconnect tests, and touch-gesture tests. Physical iPhone pairing and ARM64 hardware have not been verified by these automated checks.
