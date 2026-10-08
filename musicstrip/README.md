# 3£ — original app source and Ableton Record

## Recovery and preservation

`Source/main.m`, the existing MIDI customization bridge, all seven supporting headers, `Info.plist`, icon generator and resources were recovered from the original iCloud project at `Documents/Codex/2026-10-01/i-l/outputs/MusicStrip/Source`. The 84,361-byte main source matches the restored local iCloud file. This is not the earlier incomplete reconstruction.

The bundled original MIDI Touchbar engine (Urban Lienert, bundle ID `ch.uebe.MIDI-Touchbar`) and SnoizeMIDI framework remain binary dependencies in `recovered/`. Their original engine source has not been recovered; do not claim those binaries were compiled from our Objective-C bridge. The `DCisHurt/midiBar` GitHub project is Micro:Bit/Trill hardware firmware, not this Mac engine.

The October 7 Record installation leaves the main app's and MIDI engine's executable code unchanged. Their `__TEXT,__text` diagnostic hashes before and after the additive installation were:

- Main: `b23b58ed1593b68d6791df42a02411ef358fdf18c36e0b4e16c74e5ca0d61498`
- Engine (otool output for both architectures): `bb7bf1ed7da59d289b246217d1cbe0612cc66594e656990e75d4f6dc99ac3e60`

Code signatures change when nested resources change. The main app keeps its certificate-backed designated requirement and `local.musicstrip.app` identifier; Accessibility approval was verified after installation. Saved helper presets/defaults retain their existing bundle ID. Standard framework symlinks are tracked so a fresh checkout has a valid framework structure.

## Record control

A joined rounded control contains two equal 44-point gesture regions: Record on the left, MIDI navigation/mode on the right. Record fills red only when Live reports Arrangement Record enabled, never for an armed track; its inactive icon is white. The MIDI half uses a distinct gradient for each preset. The container and halves have explicit fixed sizing and the icons retain their aspect ratios. Both regions retain their existing taps, swipes and holds. Expanded piano replaces Record with its gesture-mode and MIDI-channel cycle controls, alongside octave adjustment. The original configured keyboard/pads remain inside the original group.

- Tap: Arrangement Record.
- Swipe right: arm Live's selected audio/MIDI track without disarming any other track, even when Live's exclusive-arm preference is enabled. The preference itself is unchanged.
- Swipe left: disarm that track. These are explicit states, not toggles.
- Hold: live-performance transport panel with Play/Pause, Stop, Arrangement Record, Punch In / Loop / Punch Out, live BPM, Tap Tempo and More.

Within that panel, tap Loop to toggle the Arrangement loop; hold it for 1/2/4/8-bar loops anchored at the current bar, halve/double length and move-brace controls. Swiping Loop moves the brace by one loop length. BPM shows Live's reported tempo: swipe for ±1 BPM, tap or hold for ±1 and ±0.1 controls. More contains Session Record, Overdub, Click, Record Quantization, Automation Arm, Re-enable Automation and quantized Stop Clips. Play resumes from the current position and pauses when already playing; Stop stops transport. Loop tools respect the current time signature (including non-4/4 signatures) and don't seek or change recording mode. All controls display acknowledged Live state, not optimistic values. New performance actions remain disabled until Live reloads the updated `_3E` script (state advertises `performance: 1`); no transport or tempo changes occur merely by opening a menu.

The performance menus use the original engine's native system-modal presentation path: AppKit's ordinary popover presentation did not display within this engine's modal bar. A native Back control returns from Loop/BPM/More to transport, then to the existing MIDI keyboard layout. Native geometry checks verified all nine transport controls, eight loop controls, four tempo controls and seven More controls within the actual 1004-point bar without clipping. Session Rec calls Live's `trigger_session_record()` to start/finish clip recording on armed tracks; it is not a simulated keyboard shortcut.

Punch In/Out use Live's existing loop-brace start/end markers. Record Quantization cycles Off, 1/8 and 1/16; it is not count-in. Live's count-in setting is intentionally not faked as a writable Song property.

`Ableton/_3E` extends the existing MIDITouchbar script with a local acknowledged-command bridge. Install it in the configured User Library's `Remote Scripts/_3E` folder. Choose **_3E** in Live's Link, Tempo & MIDI settings and set both input and output to **3£ Surface**. Only one surface instance owns the command server. The original device/parameter/channel-strip integration is unchanged; the vendor-installed original script is not edited.

The same engine's separate note/pad port is now named **3£ Keyboard**, not MIDI Touchbar User. The bridge updates only the names of endpoints obtained from its own four streams, retaining endpoint references and unique IDs. Surface and Keyboard remain separate routing roles, not separate apps. Existing Live port selections may need reselecting once after this label change; this was done in the live verification.

The app's visible branding is **3£**, but Live 12.2.5 cannot load that exact control-surface name: its loader executes `import 3£` and raises `SyntaxError: invalid character '£'`. This was verified in the live application, not guessed. **_3E** is the user-approved Python-compatible control-surface name; plain `3E` is also invalid because it begins with a number.

Commands run on Live's control-surface thread, expire after two seconds, target the current Live session and reject a changed selected track. They do not search for arbitrary Record UI controls or require Accessibility. The Touch Bar only displays recording state returned by Live; it does not optimistically invent success. Local IPC lives under `~/Library/Application Support/Strip3/AbletonRecord` (the internal compatibility path is not the displayed name).

## Reusable Piano customization

With Live's Scale Mode enabled, every native piano (including independent and expanded keyboards) highlights in-scale notes using Live's actual `root_note` and `scale_intervals`. Both key types use a cyan color family: light cyan for white keys and dark teal-cyan for black keys, preserving the keyboard's light/dark pattern. This is visual feedback only: no note filtering, transposition or MIDI routing changes. Root/scale changes redraw visible keyboards; stale/disconnected, unsupported or Scale Mode-off state restores normal colors. Black-key shapes are masked out of white-key tinting, and active keys retain the native pressed color. Restart Live once after installing the scale-feedback script update. Native render tests cover C Major, F-sharp Minor and scale-off plus unchanged note-on/off and pressed-key handling.

Customize Touch Bar uses the genuine macOS full-screen customization palette, with the original graphical control previews and drag-to-the-bottom-of-the-screen behavior. The replacement panel has been removed. The palette has **one reusable Piano Keys tile**: after a drag completes, it offers the next unused native keyboard slot, up to three. Drag items out of the physical Touch Bar to remove them; use the native **Done** button to finish. Existing layouts are not automatically replaced with three keyboards.

Each added piano is a separate instance of the original native `pianoView`, with separate active-note state, MIDI channel, gesture mode, visible octaves and starting octave. Additional instances initially use channels 2 and 3. Hold either side arrow of any keyboard to expand that piano. Its right-side controls are:

- Gesture mode: tap to cycle **GLISS** (slide across notes), **HOLD** (No Glissando: keep the original note), and **BEND** (continuous native pitchbend). Swipe left/right for previous/next. An icon and label show the active mode.
- **Ch 1–16**: tap or swipe to change this piano's MIDI channel.
- Octave count: swipe left/right to show fewer/more octaves.

The X returns from expanded mode without hiding MIDI; in normal mode it closes MIDI. Settings changes wait until all notes on that keyboard are released. Changes persist separately for the touched slot, and replacement views retain their settings identity; other pianos are unchanged. The menu-bar **Customize Controls** item is removed: piano configuration is now inside the expanded view. All pianos use **3£ Keyboard**, with channels distinguishing routing. Per-preset settings persist as `piano`, `piano2` and `piano3`.

Adding a new Piano slot preserves the controls present before the drag, even when AppKit reports a replacement layout. Deliberate removals and reordering keep native behavior. The palette also watches confirmed layout changes so a late drop commit still advances its reusable tile to the third slot. Multiple keyboards lower the original view's 400-point minimum, share equal flexible widths and fill the space left by other controls; the wrapper removes its flexible spacer for these layouts. A single keyboard retains its original minimum and sizing. Native regressions use isolated temporary presets, verify actual visible, unclipped two/three-keyboard geometry, persistence and independent note-on/off handlers, and never send MIDI to Live or change a user preset. Physical dragging remains a user verification step.

The engine presents a system-modal Touch Bar, which AppKit's normal customization action did not select. The bridge temporarily binds the actual configurable preset to AppKit's native function-row/customization controllers, waits for display geometry, and restores the original wrapped MIDI bar on Done. Private AppKit selectors are checked before use; no imitation palette is constructed. Verified the full-screen native UI and Done/reopen behavior, with the saved original layout preserved. Diagnostic state confirmed both the native controller and preview consider the application bar editable (828 × 30 physical region). Remote mouse dragging into the physical Touch Bar did not complete; physical dragging still requires the user's test. Native touch-handler diagnostics verified separate views, note-on/off channels and isolated channel changes without sending notes to Live. Quitting during customization must not reopen the Touch Bar.

## Build and additive installation

Requires macOS/Xcode command-line tools. The original engine is already vendored as a bundle dependency; no download from Documents/Downloads is required to build.

```sh
zsh musicstrip/Source/build.sh
zsh musicstrip/Source/build.sh --bridge-only
```

Full output goes to ignored `build/musicstrip/Strip3£.app`. This builds and verifies the complete package but does not replace the installed main app. Set `STRIP_SIGNING_IDENTITY` to the existing stable certificate identity on another build machine; changing signing identity may require a new macOS approval.

For the additive Record update, quit the canonical app first, then:

```sh
zsh musicstrip/install-record.sh
open '/Applications/Strip3£.app'
```

The installer updates only the injected MIDI bridge, required framework links/signatures and packaged Ableton script. It refuses to update while MusicStrip or its MIDI helper is running. It never creates an installed companion app or backup. Override `STRIP_ABLETON_SCRIPT_DIR` if your configured User Library is elsewhere. Restart Live after changing its script, then choose _3E once.

## Verification

```sh
python3 musicstrip/Tests/test_record.py
xcrun clang -fobjc-arc -O0 -Wno-unused-parameter -framework AppKit -framework CoreMIDI \
  musicstrip/Tests/record_gestures.m -o /tmp/3pounds-record-gestures
/tmp/3pounds-record-gestures
xcrun clang -fobjc-arc -O0 -Wno-unused-parameter -framework AppKit -framework CoreMIDI \
  musicstrip/Tests/multi_piano.m -o /tmp/3pounds-multi-piano-test
/tmp/3pounds-multi-piano-test
'build/musicstrip/Strip3£.app/Contents/MacOS/MusicStrip' --self-test
```

The gesture tests call the actual direct-touch handlers (including identity, movement, release, hold and cancellation), without launching another tray app or sending Live commands. `Tests/record_live.m` is an explicit opt-in diagnostic that sends actual commands to a connected Live session; do not run it on an active recording or important project. Automated tests are not a substitute for a user's finger test on the physical Touch Bar.
