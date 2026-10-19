# 3£ Phone Bar: trackpad and MIDI

The same browser UI, gestures, pairing, reconnect logic and MIDI protocol run on Windows and macOS. The host adapters supply native mouse/keyboard input and MIDI output. No phone app, account or internet connection is required once installed. Both devices must be able to reach each other on a trusted local network; a hotspot can work without an internet connection.

## Open the controller

- **Windows:** left-click the 3£Windows tray icon for its QR popup. The right-click menu also opens or stops the receiver.
- **Mac base app / TouchBar edition:** choose **Phone Bar → Show pairing QR** in the 3£ menu. This module is included in the base app; a separate Phone app is optional.
- **Mac without a Touch Bar:** the base app keeps its 3£ menu for Phone Bar and TouchTab. The optional **3E Phone.app** offers the same **Phone Bar → Show pairing QR** menu. Requires macOS 14+. Allow Accessibility for pointer and app-switching control, and Local Network / firewall access if macOS asks. If a managed helper is listed separately in Accessibility, enable that helper too.
- Scan the QR with iPhone Camera. For Apple Watch, send the same link to yourself and open it in its web viewer. Watch uses a compact layout and ordered HTTP transport.

The receiver starts only on request. The link never changes: Windows always shows `http://3e-win.local:17833/#…` and Mac `http://3e-mac.local:17833/#…`, with a saved pairing secret. When the computer's IP changes, the receiver rebinds with the same secret and the mDNS name answers with the new address, so a saved iPhone/Watch link keeps working. Wi-Fi loss pauses only the receiver, which resumes automatically when a local network returns. Making a new link (Windows: the Phone Bar row's icon) revokes the old one. A phone waking from sleep reconnects automatically while the receiver remains running. Pause one device before switching to another. HTTP stays on the LAN and is not encrypted; there is no cloud relay or router forwarding.

### Connection choices

Use the QR option for Wi-Fi/Ethernet, including a reachable local Wi-Fi hotspot. Phone Bar does not need internet. Bluetooth is not offered: phone-to-host compatibility has not been verified on either platform. There is no native iPhone Bluetooth implementation.

When mDNS is available, Mac QR codes use `http://3e-mac.local:17833` and Windows QR codes use `http://3e-win.local:17833`. Separate names keep their links unambiguous when both receivers are running on the same network. Networks that block multicast DNS continue to use the direct local IP link.

The receiver checks adapters outside the input lock, so a slow driver scan cannot block cursor commands. The browser coalesces unsent motion during short WebSocket stalls, preserves button ordering, and ignores Safari toolbar-height changes during drags. Sustained failure still releases controls and reconnects. These changes have deterministic protocol/browser tests; they are not a measurement of real iPhone radio latency.

### Module ownership

`Shared/PhoneControl` owns the receiver, gesture protocol, browser UI and MIDI mapping. `Windows/PhoneBar` supplies a separately compiled native module (`ThreeE.PhoneBar.Windows.dll`) and a lazy start/stop lifecycle; the Windows base app always references and bundles it. `MacHost` supplies the same module to the full 3£ app and the optional standalone wrapper. The base Mac build defaults to Combined and includes TouchBar, TouchTab and Phone Bar. Release checks reject incomplete base bundles. Adding or updating shared phone controls updates both hosts.

## Trackpad

Tap to click; two-finger tap right-clicks; three fingers drag. Two fingers scroll vertically or sideways (axis-locked, ignoring small drift) and keep gliding after lifting; touching the pad stops the glide. A quick two-finger sideways swipe goes back (fingers right) or forward (fingers left) using the Browser Back/Forward keys on Windows (Cmd+[ / Cmd+] on Mac); a slower sideways slide scrolls instead. Pinch to zoom (Ctrl+wheel on Windows, Cmd+= / Cmd+- on Mac). Pointer acceleration (finger speed over the last 150 ms) keeps slow motion precise; it can be turned off in Settings. Holding still never clicks. Gesture handling was informed by KDE Connect's phone touchpad (speed-based acceleration, scroll direction lock); this is an independent MIT implementation. A single tap's click waits 300 ms for a possible second touch (as on a touchpad with tap-and-drag), so tap-hold-drag never clicks first. Double-tap-hold-drag: tap, touch again within 350 ms near the same spot, hold still for 250 ms ("Drag ready"), then move. Moving straight after a tap is always a plain pointer move and never presses. Lifting an armed drag without moving cancels without clicking; a quick second tap is a double-click. The press uses `dragStart`: Windows steps the pointer just outside its double-click rectangle; macOS resets its click count. Lifting drops after a 120 ms grace period, allowing brief contact breaks. Quick double taps remain double-clicks. One-contact controls are always on (no setting): generous tap tolerance and double-tap timing. The phone dock has no scroll button; Apple Watch keeps its Scroll/Move toggle because it cannot use two fingers. Both orientations work.

Four fingers left/right change desktops. Up opens Windows Task View / Mac Mission Control. Down opens Windows desktop / Mac application windows. Mac uses the standard Control+arrow shortcuts; these must remain enabled in System Settings. Hold **Apps**, swipe left/right through Alt+Tab / Command+Tab, then lift to select. Sleep, cancellation, disconnect and rotation release mouse buttons, held app-switcher modifiers and notes from this controller.

The dock has three buttons: **⌘ Shortcuts** in the left corner, **Apps** centred, and **Media** on the right. Press ⌘ and slide onto a shortcut, then release to send it (sliding off cancels); a plain tap opens the palette for tapping. Copy/Paste/Cut sit in the row nearest the thumb. The fixed palette of Mac-style shortcuts maps to Windows: ⌘C/V/X/A, ⌘Z and ⇧⌘Z (Ctrl+Y), ⌘T, ⇧⌘T, ⌘W, ⌘N, ⌘F, ⌘S, ⌘R (F5), ⌘Space (Win+S), ⌘Q (Alt+F4) and the screenshot trio ⇧⌘3 (Win+PrtSc), ⇧⌘4 (Win+Shift+S) and ⇧⌘5 (Win+Shift+R). On macOS the same buttons send the real ⌘ shortcuts. The protocol sends only a palette id, never arbitrary keys. Hosts without a shortcut mapping hide the button.

Responsiveness: heartbeats are a few bytes and carry host state only when it changes, so dock artwork is not rebuilt every second. A touch that starts while the page is reconnecting (for example right after waking the phone) is kept and delivered once connected, and a touch after a pause sends an immediate wake packet. While the receiver runs on Windows, the app opts out of background power throttling and sets the active power plan's Wi-Fi adapter power saving to Maximum Performance; the original values are saved and restored when Phone Bar stops (or on the next start after a crash).

The icon-only **Apps** button also supports direct swipes: up shows all windows (Windows Task View / Mac Mission Control), down closes that view if open or else toggles the desktop, left moves to the previous desktop/Space, right advances to the next one. The held app chooser and arrow keys use the same direction. With only one desktop (or unavailable desktop discovery), it uses the native Alt+Tab / Command+Tab chooser instead and commits on lift. Each contact keeps one navigation mode. Tapping returns to the previous app; holding still for 500 ms opens the app chooser explicitly, regardless of desktop count. Horizontal swipes require 26 px initially, then 48 px per repeat with a 240 ms minimum interval. Vertical drags and cancelled contacts do not activate another action. Windows desktop detection reads Explorer's desktop list; Mac uses the same optional SkyLight discovery as the Touch Bar, with a window/app-switcher fallback if the OS does not expose it.

Dock buttons use icons with accessible labels. Apps uses borderless artwork as its button, with the Mac Apps/Launchpad icon when supplied by the Mac host, with a matching grid fallback on Windows. Media follows the Touch Bar's source-plus-play/pause/stop presentation, previous/next swipe feedback and piano hold symbol. The Mac base app shares its Touch Bar artwork, playback state and targeted transport, including when only the menu bar is available. Windows observes the system media session in the background and requests the registered source app's local logo once, caching a 48 px PNG or an unavailable result (up to 32 sources while the module is open). It does not scan processes or fetch website icons. An unavailable logo leaves only play/pause/stop, with no globe or placeholder source icon. Standalone Mac and hosts without media tracking also show only the playback icon; state is never guessed from taps. Media and logo discovery never run inside the pointer input lock.

When multiple sources play, the newest playing source takes priority. Pausing it hands off to a still-playing source; after all pause, Play resumes the last controlled source. Windows sends explicit play/pause/previous/next commands to that session, not a global media key, and only changes state after acknowledgement. A brief stale provider report cannot undo a confirmed pause. Closed sources are removed; unavailable commands do not redirect to another app. Windows support requires the player to expose a system media session. The optional standalone Mac wrapper retains basic system media keys; full source tracking lives in the base app.

Tap **Media** to play/pause, swipe horizontally for previous/next, swipe up for output volume, or hold for 500 ms to enter Phone Bar. The upward swipe first reveals the current laptop volume without jumping; continue up/down or use the slider to adjust it. The slider stays briefly after lifting and closes when you touch elsewhere. Volume follows the default audio output on Windows and Mac; outputs without software volume control show an unavailable slider. Audio-driver calls run outside the pointer input path, and rapid changes replace older pending values. This is laptop output volume, separate from MIDI mixer controls. The pad fills the viewport without a frame. **Trackpad** returns to the pad. On iPhone, Safari's Add to Home Screen / Open as Web App hides the browser bars; watchOS manages its own browser chrome.

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

## Keyboard and clipboard

The bottom row of the ⌘ palette has three buttons, on both Windows and Mac. Each appears only when the receiving computer reports support for it.

- **Keyboard** opens the phone keyboard and types into the focused app on the computer. Autocorrect, predictions, dictation and the space-bar cursor are replayed as backspaces, text and arrow keys. A key bar above the keyboard adds Esc, Tab, arrows, ⌫, Delete and Enter; hold an arrow or ⌫ to repeat. **Done** closes it. Text is posted as Unicode key events (Windows `KEYEVENTF_UNICODE`, Mac `CGEventKeyboardSetUnicodeString`), so accents and emoji work whatever the keyboard layout. On Mac this uses the existing Accessibility approval.
- **Paste to PC / Paste to Mac** sends what you copied on the phone: plain text, formatted text (HTML), a picture, or files such as PDFs. **Paste on …** also presses Ctrl+V / ⌘V; **Copy to … clipboard** only fills the clipboard. Pictures are converted to PNG on the phone. Windows places them as PNG + CF_DIB; Mac places them as PNG + TIFF. Files are saved to `%LOCALAPPDATA%\3EWindows\PhoneClipboard` or `~/Library/Caches/3E/PhoneClipboard`, one folder per transfer, removed after a day. They are then placed on the clipboard as files, ready to paste into Explorer/Finder, mail or chat. Maximum 200 MB per transfer.
- **Copy from PC / Copy from Mac** reads the computer clipboard and shows its text, formatted text (Mac RTF is converted to HTML), picture and copied files. **Copy text** / **Copy formatted** put them on the phone clipboard. For a picture, touch and hold it → Copy or Save to Photos. Copied files (up to 512 MB each) download to the phone. Folders are listed but not transferred.

The phone page is plain HTTP on the LAN. Browsers allow direct clipboard access only on HTTPS, so the phone uses the system Paste menu and page selection instead. Opened over HTTPS or localhost, it uses the Clipboard API directly. Transfers use authenticated same-origin POSTs (`/clipboard/write`, `/clipboard/read`, `/clipboard/item`) carrying the pairing secret. Only the connected controller can use them, and only the picture and files of the snapshot the phone just read can be downloaded. Copied HTML is shown sanitized: no scripts, styles or remote resources. Hosts opt in through `ITrackpadInput.SupportsTyping` and `ITrackpadInput.Clipboard` (`WindowsPhoneClipboard`, `MacClipboard` + `PhoneClipboard.m`).

## Source and builds

- `Web/`: shared HTML, CSS, trackpad gestures and Phone Bar controls.
- `PhoneTrackpad.cs`: bounded/authenticated listener, one-controller lease and cleanup.
- `MidiOutput.cs`: shared MIDI lifecycle and note tracking.
- `MacHost/`: CoreGraphics/CoreMIDI adapters, bundled .NET helper and native menu/QR UI.
- `../../Windows/DragEngine/ThreeFingerDragOnWindows/PhoneTrackpadWindows.cs` and `PhoneMidiWindows.cs`: Windows native adapters. The Windows app references the shared project directly.

Windows builds through `Windows/build.ps1` with .NET 10. On a Mac with Xcode command-line tools and .NET 10 SDK, run `zsh Shared/PhoneControl/MacHost/build-app.sh` for a universal standalone app; run the existing TouchBar build script for the integrated editions. Both Mac runtime architectures are bundled, so end users do not need .NET. Outputs are ad-hoc signed, not notarized. The phone workflow tests shared behavior and native Mac compilation without posting input to the CI desktop; its artifact contains the standalone app.

Tests: `dotnet run --project Windows/PhoneTrackpadTests`, then `node Windows/PhoneTrackpadTests/gestures.test.cjs`, `node Windows/PhoneTrackpadTests/trackpad.test.cjs` and `node Windows/PhoneTrackpadTests/watch.test.cjs`. `browser.test.cjs` uses installed Playwright WebKit/Chromium and the test executable's `--preview <url-file>` mode. It accepts the URL-file and screenshot-directory arguments. Preview routes input to a fake adapter and never controls the real desktop. Mac helper smoke tests are `--self-test`, `--native-self-test`, `--midi-self-test` and `--clipboard-self-test` (round-trips the real pasteboard).

Automated checks cannot establish real iPhone/Watch gesture fidelity, Accessibility approval on a user's Mac, physical Intel/ARM hardware performance, Wi-Fi latency or end-to-end Ableton audio behavior. Those require testing on the intended devices and Live session.

New phone-control source is MIT-licensed. QRCoder retains its bundled MIT license; existing repository components retain their licenses.

The Windows tray popup shows only the QR and **3£ Phone Bar**. Click outside or press Escape to dismiss it; use **Stop Phone Bar** in the tray menu to stop the receiver. If no local network is available, the popup shows the reason instead of a QR. Pairing returns basic platform/permission information immediately; MIDI output discovery runs only when the MIDI controls open or refresh, including after reconnect.
