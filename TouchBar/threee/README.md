## Touch DJ for rekordbox and Ableton

The native **Customize Touch Bar** palette includes **rekordbox · Pioneer-style Mixer** and **rekordbox · Two-deck Performance Pads**. Choose **Install / Show Touch DJ** once to place the mixer in bar 2 and the performance bank in bar 3. Installation is opt-in. The first bar and MIDI mappings remain intact; prior layouts for bars 2/3 are saved in `ThreeEDJOriginalLayoutsV1`. **Restore Layouts Before Touch DJ** restores those layouts without reinstalling on relaunch. The preset count grows to three if necessary.

Deck A is cyan and Deck B is amber. The mixer has two disc-style tempo-bend controls, channel levels, three-band EQ, color filters and a crossfader. Knobs use relative horizontal finger movement; faders use absolute horizontal position. Each disc sends momentary bend minus/plus notes, releasing the prior direction on reversal and releasing on lift, cancellation or detachment. These discs do not provide scratch jog-wheel integration. The next bar has Play/Pause, Cue, Beat Sync, Loop and eight Hot Cue pads per deck; all pads send paired Note On/Off events. Independent touch identities allow different controls to be held together.

A dedicated **3£ DJ** virtual source and destination keep DJ mappings separate from the existing Surface/Keyboard ports. Deck A uses MIDI channel 1, B channel 2. Notes 0/1/2/3 are Play/Cue/Sync/Loop, 5/6 are bend minus/plus, 16–23 are Hot Cues 1–8. CC 7 is channel level; CC 16–19 are High/Mid/Low/Filter. Global crossfader is channel 16, CC 8. All CC values are absolute 7-bit. **Touch DJ Setup…** contains the mapping reference and setup instructions.

Mappings on the 3£ side are ready. Assign the matching functions in rekordbox Performance mode → MIDI → MIDI Learn; select **3£ DJ** for input/output and use the reference's MIDI codes. The virtual device and available bend actions must be verified with the installed version. Generic MIDI Learn requires Core or higher, or compatible Hardware Unlock equipment. Some third-party functions and jog controls are restricted. No AlphaTheta identity spoofing or unsupported plug-and-play mapping import is used. See the [official MIDI Learn guide](https://cdn.rekordbox.com/files/20241203210623/rekordbox7.0.5_midi_learn_operation_guide_EN.pdf) and [rekordbox 7 FAQ](https://rekordbox.com/en/support/faq/rekordbox7/).

Received MIDI OUT notes illuminate matching pads and play state; CC feedback updates the corresponding controls without echo. Colored values/dots mark feedback received within five seconds; gray values show local controller position. PLAY/STOP is shown only from recent received play feedback. Generic MIDI does not supply track names, BPM, waveforms or audio meters. No such telemetry is fabricated. For Live, enable Track/Remote on the input and Remote on the output, then use MIDI Map; DJ-specific Cue/Sync/Hot Cue semantics depend on the mapped Live controls/devices.

Run `zsh TouchBar/threee/Tests/test_dj.sh` from the repository root. Tests cover release/cancel/reversal, MIDI isolation, CC endpoints, fragmented/running-status feedback, no echo, stale feedback, both row geometries, isolated AppKit layout migration, and a real CoreMIDI source/destination round trip. The helper's `DJ_TEST` diagnostic checks actual mounted rows and native palette identifiers. Physical finger feel and end-to-end rekordbox mapping remain manual integration checks.

# 3E — original app source and Ableton Record

The Apps launcher is a glyph-free 18-point swipe extension beside the macOS Control Strip arrow: swipe left to open apps, right to close. Its leftmost eight points fade from the native arrow's dark edge into the flat control background, softening the seam without painting outside our view. It draws no separate bezel, dots, X or divider; taps still toggle. Holding has no action and releasing a hold does not toggle the bar. The experimental Spaces-on-hold feature, native notification, visibility monitoring, delayed handoff and modal rebuilding have been removed at the user's request after physical black-bar failures. The separate media button's hold-to-open-MIDI remains unchanged. Tests check that repeated app holds make no transition and preserve normal taps, swipes and media holds. The macOS-owned arrow and its system-imposed boundary are not modified. The adjoining 52-point music control shares the same background without its old left bezel, and its icon/action pair sits three points farther left than before. Both fit the original 70-point native slot and keep their independent gestures.

The existing menu has a checked **Touch Bar App** toggle after Touch Tab, reflecting actual app-row visibility through the main/helper pipe. Menu version labels and update comparisons read the containing 3E app's Info.plist, not the helper's vendor version or stale compile-time base. Additive installs preserve the current release version; set `STRIP_RELEASE_VERSION` to the verified matching published version when syncing a new build.

The shared app/media root explicitly accepts direct Touch Bar input and forwards each finger's lifecycle to the button where it began. Crossing the 18-point app region into media during a swipe does not change targets or lose release events. Cancellation clears tracking and hold timers. Tests cover both input regions, boundary-crossing swipes, app hold inactivity, media holds and cancellation. Physical confirmation is still needed after input changes. `AppsLauncherLastInput` records only the host PID, command and timestamp for an actual app-button action; it contains no app, media or MIDI content.

## Recovery and preservation

Version 3.0.11 uses `3E.app` for the installed app and release archives. Its
bundle identifier, certificate-backed signing identity and preferences remain
unchanged. The historical recovered dependency retains its archive filename.

Window swipes query actual app windows asynchronously, without blocking the
Touch Bar main thread. If a finger lifts before that query finishes, the chooser
stays visible; a subsequent touch selects a returned window. Empty responses no
longer trigger synthetic Command-backtick window cycling, and retries terminate
with an explicit status instead of an infinite loading label. The chooser
regression checks delayed lift, identical window titles, selection and cancel.
Releasing a resolved empty window picker restores the app row immediately.
If the finger lifts during a pending query, real late-arriving windows stay
selectable; a final empty response automatically restores apps instead of
leaving a frozen message. Permission failures follow the same dismissal rule.

On this development Mac, the actual LaunchServices host reported Accessibility
denied and System Settings showed the old app entry off. Touch Tab's preference
was also off and was enabled. macOS authentication is required to refresh the
existing permission for `/Applications/3E.app`; code cannot grant it. Do not claim
that gesture/window access works merely because a terminal test inherits Codex's
permissions. `TouchTabRuntimeState` records the real host PID, bundle path,
authorization and listener state; `WindowAccessRuntimeState` records read-only AX
window counts after the real host becomes authorized (not window titles).

The combined menu places Touch Tab immediately below Phone Bar, then lists Touch Bar Midi and Control Surface Mode. Labels stay fixed; checks reflect the real gesture listener, MIDI visibility and combined surface panel respectively. Clicking an unchecked, permission-blocked Touch Tab retries activation and requests Accessibility approval for the actual main app; it does not accidentally disable the saved preference. Permission prompts occur only on that explicit menu action, never in the polling timer. Approval starts the listener automatically on the next refresh.

On October 11 the macOS permission log identified the enabled-but-denied cause: the stored approval required an obsolete binary `cdhash`, failing code-requirement validation (`-67050`) against the certificate-signed current app. Toggling the old entry did not replace that requirement. Removing only its Device Control and Data Access entry, adding the exact installed `/Applications/3E.app` through the system chooser, and restarting fixed the actual host: AX trust, event-listening access, event-posting access and the gesture listener all reported true. No TCC database edits or global resets were used. The engine now tests an actual enabled event tap and posting permission rather than treating AX trust alone as gesture readiness; runtime diagnostics include both input capabilities. This does not prove a physical swipe was performed; verify that interactively after permission recovery.

`Source/main.m`, the existing MIDI customization bridge, all seven supporting headers, `Info.plist`, icon generator and resources were recovered from the original iCloud project at `Documents/Codex/2026-10-01/i-l/outputs/ThreeE/Source`. The 84,361-byte main source matches the restored local iCloud file. This is not the earlier incomplete reconstruction.

The bundled original MIDI Touchbar engine (Urban Lienert, bundle ID `ch.uebe.MIDI-Touchbar`) and SnoizeMIDI framework remain binary dependencies in `recovered/`. Their original engine source has not been recovered; do not claim those binaries were compiled from our Objective-C bridge. The `DCisHurt/midiBar` GitHub project is Micro:Bit/Trill hardware firmware, not this Mac engine.

The October 7 Record installation leaves the main app's and MIDI engine's executable code unchanged. Their `__TEXT,__text` diagnostic hashes before and after the additive installation were:

- Main: `b23b58ed1593b68d6791df42a02411ef358fdf18c36e0b4e16c74e5ca0d61498`
- Engine (otool output for both architectures): `bb7bf1ed7da59d289b246217d1cbe0612cc66594e656990e75d4f6dc99ac3e60`

Code signatures change when nested resources change. The main app keeps its certificate-backed designated requirement and `local.musicstrip.app` identifier; Accessibility approval was verified after installation. Saved helper presets/defaults retain their existing bundle ID. Standard framework symlinks are tracked so a fresh checkout has a valid framework structure.

## Record control

MIDI preset navigation is a fixed 44-point segment beside the original left-side X. The 32-point Record control immediately follows the joined X/navigation item, preserving its size, shape, colors and behavior. It fills red only when Live reports Arrangement Record enabled, never for an armed track; its inactive icon is white. Preset navigation uses a distinct gradient for each preset; holding it does not switch modes. MIDI channel is configured through Customize Controls. The original configured keyboard/pads remain inside the original group.

Customize Controls saves the visible color picker's current value, not the vendor editor's potentially stale cached color. The original color archive format is retained. The native `CONTROLS_COLOR_TEST` exercises selection, picker changes, writing and actual Apply/live-button updates for the configured CC1–4 pads, verifies their mappings are unchanged, and restores the original palette afterwards. `CONTROL_COLOR_STATUS` compares saved and live colors and renders attached pads for visual checking.

- Tap: Arrangement Record.
- Swipe right: arm Live's selected audio/MIDI track set without disarming any other track, even when Live's exclusive-arm preference is enabled. The preference itself is unchanged.
- Swipe left: disarm those tracks. These are explicit states, not toggles.
- Hold: combined native control surface and arrangement panel. Hold the same left-side Record control again to return directly to MIDI, including from nested menus.

The update section contains “Automatically Install Updates”; “Check for Update” and “Check for Update on launch” menu items are removed. Automatic background checks continue and install newer releases when the preference is enabled.

Within that panel, tap the combined Loop/Punch control to toggle the Arrangement loop; swipe left to toggle Punch In or right to toggle Punch Out. Separate illuminated cues show each acknowledged state. Hold it for 1/2/4/8-bar loops anchored at the current bar, halve/double length and move-brace controls. BPM shows Live's reported tempo: tap for Tap Tempo, swipe for ±1 BPM, or hold for ±1 and ±0.1 controls. More contains Session Record, Overdub, Click, Record Quantization, Automation Arm, Re-enable Automation and quantized Stop Clips. Loop tools respect the current time signature (including non-4/4 signatures) and don't seek or change recording mode. All controls display acknowledged Live state, not optimistic values. New performance actions remain disabled until Live reloads the updated `_3E` script (state advertises `performance: 1`); no transport or tempo changes occur merely by opening a menu.

The performance menus use the original engine's native system-modal presentation path. The panel embeds the original channel/device control strip and its eight-fader device page rather than recreating them. It has no preset navigation, X, Play, Stop, separate Tap or duplicate Record controls. The 76-point Loop control occupies the same left slot as the normal MIDI X/preset navigation group, so Record stays aligned across modes; BPM and More follow Record, and the native control surface sits at the far right. A short Record swipe arms/disarms the selected track in normal mode. In the combined Control Surface panel, a right swipe arms only the selected track and a left swipe toggles all armable tracks; neither requires a hold. Holding Record without swiping opens recording options. Tapping Loop toggles Arrangement Loop; the Loop item retains its active-state indication and left/right Punch In/Out swipes. The menu-bar Control Surface Mode entry opens this same combined panel. Session Rec calls Live's `trigger_session_record()` to start/finish clip recording on armed tracks; it is not a simulated keyboard shortcut.

The surface is initialized through the vendor bar's item factory, not its initially blank item property. Record hold enters native control-surface mode, preserving and restoring the previous mode on return. The menu entry uses that same route even when MIDI is hidden, rather than falling back to the vendor's separate bar. Selecting it again returns to MIDI; its checkmark follows the actual combined panel. Its actual view is hosted with enough space for the native faders and labels; regression tests exercise the real menu from both visible and hidden MIDI and require those real regions, not merely a visible placeholder.

BPM swipes are proportional: every four Touch Bar points of horizontal travel changes tempo by approximately 1 BPM (20–999 BPM limits). The target is measured from the starting tempo, so reversing the swipe reverses the change. The latest absolute target is coalesced while awaiting Live acknowledgment; it is not dropped or applied to another Live session. Tap Tempo and held fine/coarse controls remain available. Restart Live to enable the new `tempo_drag` capability and `tempo-set` command: changing the surface selector alone can reuse the already-imported Python module. Loop and BPM collapsed representations use fixed plain-view hosts, preventing NSButton alignment outsets from clipping the Punch In/Out icons or the swipe area. Native tests require each button's entire bounds to fit within every containing view.

Older already-loaded scripts also support proportional BPM swipes without a restart. The app translates the latest target into bounded batches of their existing tempo-up/down operations, waits for every acknowledgment, and recalculates from reported Live tempo before sending more. Reversals replace the queued target; a changed Live session cancels it. New scripts still use the single absolute `tempo-set` command. This compatibility path uses only tempo operations and never changes recording, track selection, or the current set.

Punch In/Out use Live's existing loop-brace start/end markers. Record Quantization cycles Off, 1/8 and 1/16; it is not count-in. Live's count-in setting is intentionally not faked as a writable Song property.

`Ableton/_3E` extends the existing MIDITouchbar script with a local acknowledged-command bridge. Install it in the configured User Library's `Remote Scripts/_3E` folder. Choose **_3E** in Live's Link, Tempo & MIDI settings and set both input and output to **3E Surface**. Only one surface instance owns the command server. The original device/parameter/channel-strip integration is unchanged; the vendor-installed original script is not edited.

The same engine's separate note/pad port is now named **3E Keyboard**, not MIDI Touchbar User. The bridge updates only the names of endpoints obtained from its own four streams, retaining endpoint references and unique IDs. Surface and Keyboard remain separate routing roles, not separate apps. Existing Live port selections may need reselecting once after this label change; this was done in the live verification.

The app's visible branding is **3E**, but Live 12.2.5 cannot load that exact control-surface name: its loader executes `import 3E` and raises `SyntaxError: invalid character '£'`. This was verified in the live application, not guessed. **_3E** is the user-approved Python-compatible control-surface name; plain `3E` is also invalid because it begins with a number.

Commands run on Live's control-surface thread, expire after two seconds, target the current Live session and reject a changed primary selected track. Record swipes read Ableton's selected track rows so a multi-selection arms or disarms every selected armable track in normal mode. In Control Surface mode, a right swipe arms every selected armable track and disarms all other armable tracks; a left swipe keeps its all-track toggle. Reading selected rows requires Accessibility approval for 3E; if approval is unavailable, swipes fall back to the primary selected track. The Touch Bar only displays recording state returned by Live; it does not optimistically invent success. Local IPC lives under `~/Library/Application Support/Strip3/AbletonRecord` (the internal compatibility path is not the displayed name).

## Reusable Piano customization

With Live's Scale Mode enabled, every native piano (including independent and expanded keyboards) highlights in-scale notes using Live's actual `root_note` and `scale_intervals`. Both key types use a cyan color family: light cyan for white keys and dark teal-cyan for black keys, preserving the keyboard's light/dark pattern. This is visual feedback only: no note filtering, transposition or MIDI routing changes. Root/scale changes redraw visible keyboards; stale/disconnected, unsupported or Scale Mode-off state restores normal colors. Black-key shapes are masked out of white-key tinting, and active keys retain the native pressed color. Restart Live once after installing the scale-feedback script update. Native render tests cover C Major, F-sharp Minor and scale-off plus unchanged note-on/off and pressed-key handling.

Customize Touch Bar uses the genuine macOS full-screen customization palette, with the original graphical control previews and drag-to-the-bottom-of-the-screen behavior. The replacement panel has been removed. The palette has **one reusable Piano Keys tile**: after a drag completes, it offers the next unused native keyboard slot, up to three. Drag items out of the physical Touch Bar to remove them; use the native **Done** button to finish. Existing layouts are not automatically replaced with three keyboards.

Each added piano is a separate instance of the original native `pianoView`, with separate active-note state, MIDI channel, gesture mode, visible octaves and starting octave. Additional instances initially use channels 2 and 3. Hold either side arrow of any keyboard to expand that piano. Its left-side joined controls are Close, gesture mode, visible octaves and scale-degree labels, all in the selected preset's color. This replaces preset navigation while expanded:

- Gesture mode: tap to cycle **GLISS** (slide across notes), **HOLD** (No Glissando: keep the original note), and **BEND** (continuous native pitchbend). Swipe left/right for previous/next. An icon and label show the active mode.
- Octave count: swipe left/right to show fewer/more octaves.
- Playing area: black-key hit boxes follow the actual visible contours, including rounded lower corners, clipped to the keyboard. White hits wrap around those contours and fill the small visual gutters; below the black keys is a continuous white-key lane. There is no artificial halfway-height cutoff. Glissando, Hold and Pitchbend retain their existing behavior; drawing and edge-arrow hit regions are unchanged. Native tests cover narrow/wide keyboards, 1/3/10 octaves, and half-octave shifts without sending MIDI to Live.
- Scale degrees: tap the **harmony icon** to show or hide top-aligned Roman numerals on in-scale keys, using Live's current root and scale. Cyan glow and a status dot indicate enabled; a dim icon indicates disabled. The choice is independent for each keyboard. Seven-note scales indicate the scale-derived triad's major/minor/diminished/augmented quality; these labels do not detect played chords or invent seventh extensions.

Piano-only presets with two or three keyboards use a cached shared row with two-point inter-piano gaps. Width comes from the measured native Touch Bar host, with equal pixel-aligned piano frames prepared before presentation. A periodic sizing refresh does not install late equal-width constraints on this row. Mixed-control presets and the native customization palette retain their original item workflow. Native regression tests switch away and back six times and check immediate widths, refresh stability, gap size, and MIDI notes.

Expanded Close, gesture mode, octave count, and scale-degree visibility share one gapless, rounded 132-point item at the left of the keyboard. Close is 32 points, gesture mode and octave count are 36 points each, and the still narrower Labels segment is 28 points. The gesture symbol is above its GLISS/HOLD/BEND label, the octave number is above a small keyboard-span symbol (no OCT text), and the smaller harmony icon toggles Roman-numeral scale-degree labels for this piano only. Each control retains independent touch tracking; channel settings remain in Customize Controls. Degree visibility survives octave replacement and is saved with each piano's preset settings.

Both piano side arrows keep compact fixed 14-point areas regardless of octave count. Tap retains the arrow's original previous/next half-octave action; on either arrow, swipe right advances and swipe left goes back by one half octave. A swipe does not also trigger a tap or hold. Holding either arrow expands that piano. Keys fill the space immediately between those edges instead of shrinking the arrows. Dense keyboards proportionally scale native key shapes and gutters, preventing fixed pixel gaps from consuming narrow keys.

The native key paths and pressed-note colors are rendered without the vendor's independently calculated chevrons, preventing ghost arrows on the final keys. A single pair of 14-point arrows shares its bounds-based regions with hold/tap handling, so stale native arrow paths cannot disable the right-side hold. Regression tests press the last key at 1, 2 and 10 octaves, check its pixels for unwanted arrows, and test both sides of all three piano slots.

The X returns from expanded mode without hiding MIDI; in normal mode it closes MIDI. Settings changes wait until all notes on that keyboard are released. Changes persist separately for the touched slot, and replacement views retain their settings identity; other pianos are unchanged. The menu-bar **Customize Controls** item retains the original controls workflow, including MIDI channel and other settings. Only the piano's Glissando/Type selector is hidden there; gesture mode stays in the expanded piano, which has no channel button. All pianos use **3E Keyboard**, with channels distinguishing routing. Per-preset settings persist as `piano`, `piano2` and `piano3`.

Adding a new Piano slot preserves the controls present before the drag, even when AppKit reports a replacement layout. Deliberate removals and reordering keep native behavior. The palette also watches confirmed layout changes so a late drop commit still advances its reusable tile to the third slot. Multiple keyboards lower the original view's 400-point minimum, share equal flexible widths and fill the space left by other controls; the wrapper removes its flexible spacer for these layouts. A single keyboard retains its original minimum and sizing. Native regressions use isolated temporary presets, verify actual visible, unclipped two/three-keyboard geometry, persistence and independent note-on/off handlers, and never send MIDI to Live or change a user preset. Physical dragging remains a user verification step.

The engine presents a system-modal Touch Bar, which AppKit's normal customization action did not select. The bridge temporarily binds the actual configurable preset to AppKit's native function-row/customization controllers, waits for display geometry, and restores the original wrapped MIDI bar on Done. Private AppKit selectors are checked before use; no imitation palette is constructed. Verified the full-screen native UI and Done/reopen behavior, with the saved original layout preserved. Diagnostic state confirmed both the native controller and preview consider the application bar editable (828 × 30 physical region). Remote mouse dragging into the physical Touch Bar did not complete; physical dragging still requires the user's test. Native touch-handler diagnostics verified separate views, note-on/off channels and isolated channel changes without sending notes to Live. Quitting during customization must not reopen the Touch Bar.

## Build and additive installation

### Customize Controls (3.0.10)

Opening the original editor retains the actual selected MIDI preset instead of
presenting the empty modal wrapper. Physical touches select controls again;
each of the three piano identifiers uses the same editor and its own saved
MIDI channel. Piano mode, octave count and starting octave are hidden here and
remain controlled by the expanded piano. Applying other piano settings preserves
those values and refreshes the live preset without resizing the outer buttons.

The header shows the current preset number and a **Bars** up/down selector
(1–9, the original engine's available presets). Reducing the count hides presets
from cycling without deleting their layouts or mappings; increasing restores
them. The count is saved across launches.

Isolated engine diagnostics: `SHOW`, `CONTROLS_TEST`, `CONTROLS_APPLY_TEST`.
These check the actual touch-began selection route for three independent pianos,
pad selection, title, count changes, preserved expanded settings, and real native
Apply/live reload. The Apply test restores its temporary channel change. Native
two/three-piano sizing/note regressions also pass. Final physical finger testing
is still required on the Touch Bar.

The default `zsh threee/Source/build.sh` builds the full Combined base app with TouchBar, TouchTab and Phone Bar. `--combined` remains an alias; use `--touchbar-only` explicitly for the smaller edition. The combined app embeds the shared TouchTab Swift gesture module in its main process, adds a **Touch Tab** menu toggle through the existing MIDI-helper pipe, and preserves the original MIDI engine. On the development Mac, quit 3E and run `zsh threee/install-combined.sh` for an in-place installation. The main executable is rebuilt from the maintained original source with narrowly scoped gesture lifecycle/pipe hooks; the working app-picker helper, piano engine, resources, MIDI mappings and user settings are retained. Root README describes the separate combined/standalone update feeds and permissions.

Requires macOS/Xcode command-line tools. The original engine is already vendored as a bundle dependency; no download from Documents/Downloads is required to build.

```sh
zsh threee/Source/build.sh
zsh threee/Source/build.sh --bridge-only
```

Full output goes to ignored `build/threee/3E.app`. This builds and verifies the complete package but does not replace the installed main app. Set `STRIP_SIGNING_IDENTITY` to the existing stable certificate identity on another build machine; changing signing identity may require a new macOS approval.

For the additive Record update, quit the canonical app first, then:

```sh
zsh threee/install-record.sh
open '/Applications/3E.app'
```

The installer updates only the injected MIDI bridge, required framework links/signatures and packaged Ableton script. It refuses to update while ThreeE or its MIDI helper is running. It never creates an installed companion app or backup. Override `STRIP_ABLETON_SCRIPT_DIR` if your configured User Library is elsewhere. Restart Live after changing its script, then choose _3E once.

## Verification

In 3.0.9 the actual `showTouchbar:` preset-switch path is intercepted: it no longer empties the live root or copies identifiers into the presentation shell. A stable outer group swaps the selected original preset content; close/navigation/record controls are retained. A permanent flexible spacer absorbs unused space instead of stretching controls, and the outer group is not a principal item. Two/three-piano content uses a uniquely identified compact row (not the outer group's identifier). Native regressions exercise `receivedGlobalKeyFrom:key:` and assert presentation identity, serial, fixed control widths, unchanged piano widths and two-point gaps. Finger-perceived smoothness still needs physical verification.

Multi-piano presentation is prepared before opening: the flexible spacer is omitted from the initial outer row, equal sizing is applied synchronously without implicit animation, and unchanged width constraints are retained across refreshes. Multi-piano groups use AppKit's compact alert-style grouping. Arrow regions are fixed at 14 points on each side (formerly 18), reclaiming 8 points per piano for keys while preserving arrow taps/holds. Native tests cover two/three-piano row stability and dense arrow hit regions through ten octaves; perceived switching smoothness still requires a physical finger test.

```sh
python3 threee/Tests/test_record.py
xcrun clang -fobjc-arc -O0 -Wno-unused-parameter -framework AppKit -framework CoreMIDI \
  threee/Tests/record_gestures.m -o /tmp/3pounds-record-gestures
/tmp/3pounds-record-gestures
xcrun clang -fobjc-arc -O0 -Wno-unused-parameter -framework AppKit -framework CoreMIDI \
  threee/Tests/multi_piano.m -o /tmp/3pounds-multi-piano-test
/tmp/3pounds-multi-piano-test
'build/threee/3E.app/Contents/MacOS/ThreeE' --self-test
```

The gesture tests call the actual direct-touch handlers (including identity, movement, release, hold and cancellation), without launching another tray app or sending Live commands. `Tests/record_live.m` is an explicit opt-in diagnostic that sends actual commands to a connected Live session; do not run it on an active recording or important project. Automated tests are not a substitute for a user's finger test on the physical Touch Bar.
