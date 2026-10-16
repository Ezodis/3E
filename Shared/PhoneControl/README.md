# 3£ Phone Bar: trackpad and MIDI

The same browser UI, gestures, pairing, reconnect logic and MIDI protocol run on Windows and macOS. The host adapters supply native mouse/keyboard input and MIDI output. No phone app, account or internet connection is required once installed. Both devices must be able to reach each other on a trusted local network; a hotspot can work without an internet connection.

## Open the controller

- **Windows:** left-click the 3£Windows tray icon for its QR popup. The right-click menu also opens or stops the receiver.
- **Mac base app / TouchBar edition:** choose **Phone Bar → Show pairing QR** in the 3£ menu. This module is included in the base app; a separate Phone app is optional.
- **Mac without a Touch Bar:** the base app keeps its 3£ menu for Phone Bar and TouchTab. The optional **3E Phone.app** offers the same **Phone Bar → Show pairing QR** menu. Requires macOS 14+. Allow Accessibility for pointer and app-switching control, and Local Network / firewall access if macOS asks. If a managed helper is listed separately in Accessibility, enable that helper too.
- Scan the QR with iPhone Camera. For Apple Watch, send the same link to yourself and open it in its web viewer. Watch uses a compact layout and ordered HTTP transport.

The receiver starts only on request. Wi-Fi loss stops only the receiver; start it again after reconnecting. Every receiver restart creates a new link. A phone waking from sleep reconnects automatically while the receiver remains running. Pause one device before switching to another. HTTP stays on the LAN and is not encrypted; there is no cloud relay or router forwarding.

### Connection choices

Use the QR option for Wi-Fi/Ethernet, including a reachable local Wi-Fi hotspot. Phone Bar does not need internet. Bluetooth is not offered: phone-to-host compatibility has not been verified on either platform. There is no native iPhone Bluetooth implementation.

The receiver checks adapters outside the input lock, so a slow driver scan cannot block cursor commands. The browser coalesces unsent motion during short WebSocket stalls, preserves button ordering, and ignores Safari toolbar-height changes during drags. Sustained failure still releases controls and reconnects. These changes have deterministic protocol/browser tests; they are not a measurement of real iPhone radio latency.

### Module ownership

`Shared/PhoneControl` owns the receiver, gesture protocol, browser UI and MIDI mapping. `Windows/PhoneBar` supplies a separately compiled native module (`ThreeE.PhoneBar.Windows.dll`) and a lazy start/stop lifecycle; the Windows base app always references and bundles it. `MacHost` supplies the same module to the full 3£ app and the optional standalone wrapper. The base Mac build defaults to Combined and includes TouchBar, TouchTab and Phone Bar. Release checks reject incomplete base bundles. Adding or updating shared phone controls updates both hosts.

## Trackpad

Tap to click; two-finger tap right-clicks; two fingers scroll; three fingers drag. Tap, then touch again within 500 ms and move to drag: the second touch presses immediately. Lifting drops after a 120 ms grace period, allowing brief contact breaks. Quick double taps remain double-clicks. Single-contact mode in Settings lengthens the second-tap window to 650 ms, offers Scroll/Move, and supports holding still to right-click. Both orientations work.

Four fingers left/right change desktops. Up opens Windows Task View / Mac Mission Control. Down opens Windows desktop / Mac application windows. Mac uses the standard Control+arrow shortcuts; these must remain enabled in System Settings. Hold **Apps**, swipe left/right through Alt+Tab / Command+Tab, then lift to select. Sleep, cancellation, disconnect and rotation release mouse buttons, held app-switcher modifiers and notes from this controller.

Tap **Media** to play/pause, swipe for previous/next, or hold for 500 ms to enter Phone Bar. **Trackpad** returns to the pad. On iPhone, Safari's Add to Home Screen / Open as Web App hides the browser bars; watchOS manages its own browser chrome.

## Ableton setup and Phone Bar

1. Windows: create a virtual MIDI loopback port, for example **3E Phone**, using [loopMIDI](https://www.tobias-erichsen.de/software/loopmidi.html), and choose it in Phone Bar's Output list. The app does not install a driver. Use Refresh outputs after creating a port. Windows MIDI output starts off until selected.
2. Mac: the receiver creates its own **3E Phone** CoreMIDI source. No loopback driver is required.
3. In Ableton's **Link, Tempo & MIDI** settings, enable **Remote** for that input. Enter **MIDI Map** (Ctrl+M / Cmd+M), select a Live control, and move its counterpart on the phone. Leave MIDI Map mode to perform. [Ableton mapping guide](https://help.ableton.com/hc/en-us/articles/360000038859-Making-custom-MIDI-Mappings) · [Virtual MIDI buses](https://help.ableton.com/hc/en-us/articles/209774225-Setting-up-a-virtual-MIDI-bus).

Phone Bar has two decks and an eight-track mixer. Drag through a knob's centre vertically (up increases / clockwise), or move around its rim to turn it. Double-tap a knob to reset. Drag a vinyl rim to send relative jog steps; keyboard arrows also work. Mixer and deck controls for the same track share their values.

For a two-track mix, load audio into two Live tracks, assign them to crossfader sides A and B, and map Launch, Stop, Cue, level, EQ, sends and the crossfader. The jog wheels send Relative (Bin Offset) CC values; choose that mapping mode for a compatible parameter in Live. This is a MIDI control surface, not an audio player, stem separator, tempo-sync engine or automatic mashup generator. Vinyl animation reflects local Launch/Stop taps rather than playback feedback. Mute/solo highlights also show local taps, not Live's state. Mapping and actual audio performance require setup in your Live session.

Default channel is **16** (wire channel 15). Both layouts use the same mapping:

| Control | MIDI message |
| --- | --- |
| Crossfader | CC 1 |
| Track 1–8 level | CC 16–23 (decks A/B: 16/17) |
| Track 1–8 pan | CC 24–31 |
| Track 1–8 send | CC 32–39 (decks A/B: 32/33) |
| Jog A/B | CC 40/41, 65 clockwise, 63 counterclockwise |
| Filter A/B | CC 48/49 |
| Low / Mid / High A/B | CC 50/51, 52/53, 54/55 |
| Launch / Cue / Stop A/B | Notes 36/37, 38/39, 42/43 |
| Track 1–8 mute / solo | Notes 48–55 / 56–63 |

Triggers send a note-on followed by note-off. **Release notes** sends releases only for this controller's held notes. It does not silence other MIDI devices. Port changes, sleep and disconnect also release held notes. No mappings or output-port selections are silently written to Ableton preferences.

## Source and builds

- `Web/`: shared HTML, CSS, trackpad gestures and Phone Bar controls.
- `PhoneTrackpad.cs`: bounded/authenticated listener, one-controller lease and cleanup.
- `MidiOutput.cs`: shared MIDI lifecycle and note tracking.
- `MacHost/`: CoreGraphics/CoreMIDI adapters, bundled .NET helper and native menu/QR UI.
- `../../Windows/DragEngine/ThreeFingerDragOnWindows/PhoneTrackpadWindows.cs` and `PhoneMidiWindows.cs`: Windows native adapters. The Windows app references the shared project directly.

Windows builds through `Windows/build.ps1` with .NET 10. On a Mac with Xcode command-line tools and .NET 10 SDK, run `zsh Shared/PhoneControl/MacHost/build-app.sh` for a universal standalone app; run the existing TouchBar build script for the integrated editions. Both Mac runtime architectures are bundled, so end users do not need .NET. Outputs are ad-hoc signed, not notarized. The phone workflow tests shared behavior and native Mac compilation without posting input to the CI desktop; its artifact contains the standalone app.

Tests: `dotnet run --project Windows/PhoneTrackpadTests`, then `node Windows/PhoneTrackpadTests/gestures.test.cjs` and `node Windows/PhoneTrackpadTests/watch.test.cjs`. `browser.test.cjs` uses installed Playwright WebKit/Chromium and the test executable's `--preview <url-file>` mode. It accepts the URL-file and screenshot-directory arguments. Preview routes input to a fake adapter and never controls the real desktop. Mac helper smoke tests are `--self-test`, `--native-self-test` and `--midi-self-test`.

Automated checks cannot establish real iPhone/Watch gesture fidelity, Accessibility approval on a user's Mac, physical Intel/ARM hardware performance, Wi-Fi latency or end-to-end Ableton audio behavior. Those require testing on the intended devices and Live session.

New phone-control source is MIT-licensed. QRCoder retains its bundled MIT license; existing repository components retain their licenses.

The Windows tray popup shows only the QR and **3£ Phone Bar**. Click outside or press Escape to dismiss it; use **Stop Phone Bar** in the tray menu to stop the receiver. If no local network is available, the popup shows the reason instead of a QR. Pairing returns basic platform/permission information immediately; MIDI output discovery runs only when the MIDI controls open or refresh, including after reconnect.
