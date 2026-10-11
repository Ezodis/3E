# Touch Bar + Ableton: reusable tap/hold rhythms

Saved October 11, 2026 from the working Controlla setup. This kit preserves the Touch Bar MIDI layouts, the tap/hold Max for Live device, the drum sounds, and the rhythm notes. It can live anywhere outside Documents/Codex. It does not need the original full song or its audio stems.

## Start here

1. Extract the entire `TouchBar-Ableton.zip` together into your Music folder or Ableton User Library. Keep its subfolders together.
2. Use Ableton Live 12.2.5 or newer with Max for Live, and the 3£ Touch Bar app from this repository. A physical Touch Bar is needed for the hardware controls.
3. Open `TouchBar Rhythm Starter.als`. This is a copy containing AI DRUMS and SONG RHYTHMS, plus the existing return effects. The original song project is untouched. Both MIDI tracks are saved disarmed.
4. In Live's MIDI settings, enable **Track** input for **3£ Keyboard**. The separate **3£ Surface** port is for the `_3E` control-surface script, not these drum buttons. The script already lives at `TouchBar/musicstrip/Ableton/_3E` in this repository. Its transport integration is optional for the tap/hold device.
5. AI DRUMS should have Monitor **In**. SONG RHYTHMS should have Monitor **Off** and MIDI To **AI DRUMS / Track In**. These routings are preserved in the starter.
6. Use your first Touch Bar preset: piano plus four momentary CC pads. If restoring on another Mac, follow Configuration below.
7. Start playback. Tap a pad for a hit, or hold it for about 300 ms to let that part of the rhythm through. Release stops new hits; a sample already playing may finish its tail.

For a quick audible example, launch `Bars 37-40 - Original` in SONG RHYTHMS and hold Kick or Hat. The first four bars contain only six kick notes, with silence before the first note, so the first clip is not a good test of every button. If you launch a Session clip, use **Back to Arrangement** to return to the song timeline. Changing between Session and Arrangement views alone does not change the playback source.

## What is stored

- `Devices/Touchbar Original Song Follow.amxd`: ready-to-load Max for Live MIDI effect.
- Matching `.maxpat`: editable source, including the 300 ms hold threshold and CC/note routing.
- `Devices/Controlla - Original AI Drums.adg`: reusable Drum Rack with the six samples under `Samples/`.
- `TouchBar Rhythm Starter.als`: two MIDI tracks with the device, rack, routing, 11 Session loops, and one 43-bar Arrangement clip.
- `Rhythms/*.mid`: independent standard MIDI exports of all 11 excerpts and the complete rhythm, with original note timing and velocity. No fixed tempo event is embedded; use the destination project's tempo. MIDI files do not preserve Live launch settings, so enable Loop and set the length when importing.
- `Rhythms/clip-index.json`: clip lengths and note counts.
- `Configuration/TouchBar-MIDI-presets.plist`: actual saved preset layouts, control assignments, colors, keyboard settings, preset count, and hotkeys. Includes saved hidden layouts so they can be recovered. Machine-specific port IDs, window positions, test presets, and unrelated app settings are excluded.
- `Configuration/restore-presets.py`: preview/restore helper that backs up existing preferences and merges only these saved keys.

## CC controls and drum notes are different

CC means Control Change: a numbered control message. A MIDI note selects the sound/pad. Here a CC button opens a gate for particular notes; adding a CC number alone does not create a sound or a rhythm.

| Touch Bar pad | Message, MIDI channel 1 | Tap note | Notes allowed while held |
| --- | --- | --- | --- |
| Kick | CC1, press 127 / release 0 | 36 | 36 |
| Snare | CC2, press 127 / release 0 | 38 | 38 |
| Hat | CC3, press 127 / release 0 | 42 | 42 |
| Perc | CC4, press 127 / release 0 | 37 | 37, 56, 45 |

Use **momentary**, not toggle, buttons: releasing must send zero. The current device listens to CC1–4 on all incoming MIDI channels and outputs notes on channel 10. Filter incoming ports/channels in Live if another controller uses the same CCs. Pitch numbers are authoritative because octave labels vary between apps.

## Reuse in another song

**Same rhythm, different sounds:** replace samples in the Drum Rack while keeping its incoming note assignments (36, 38, 42, 37, 56, 45). Save the new rack under a new name. The timing remains unchanged. You can also use another instrument that responds to these notes; its pitch/sound mappings must match what you want.

**Same rhythm, different tempo:** change Live's project BPM. MIDI notes follow the project beat grid. These excerpts are in 4/4: four bars = 16 beats; the last excerpt is three bars = 12 beats. A different time signature changes how those beat lengths fit into bars. The saved working set used 120 BPM; the old source filenames' “94bpm” label is not the current project tempo.

**Import into another project:** add this extracted folder to Live's browser, expand the starter `.als`, and drag both MIDI tracks into the destination. Check SONG RHYTHMS → AI DRUMS / Track In after import. Or create the two tracks manually, load the `.amxd` before the `.adg`, and import a MIDI file onto SONG RHYTHMS. Save As and use Collect All and Save for each new project.

**Follow a new song's own drums:** replace/edit the MIDI notes in SONG RHYTHMS with the new song's rhythm. The device does not listen to an audio song and automatically discover its beat. These are stored patterns from this particular setup.

**Session loops versus the full song:** Session has 11 alternatives, split across bars 1–43. One clip in the track plays at a time. They loop rather than automatically progressing down the list. Arrangement has a single full-length rhythm following the playhead. Pressing a pad does not restart that clip: the initial manual hit is immediate, and the held gate then joins incoming notes at their current position. A Session clip takes priority over that track's Arrangement until Back to Arrangement is used.

## Fewer or more controls

- Fewer: keep just the pads you need in Customize Touch Bar. Retain their CC numbers. Unused parts remain closed.
- More sounds together: Perc already gates three notes with one button. You can group additional sounds behind a control by editing the Max routing.
- More independently held parts: add momentary CC pads in Customize Controls AND extend the `.maxpat` with another CC input, press/release logic, 300 ms delay, note gate, and output note. Wire the new gate into Release all too. Simply adding CC5 to the Touch Bar will do nothing in the unmodified four-control device.
- More presets: the app's **Bars** setting means the number of Touch Bar layouts (1–9), not musical measures. The saved value is 3. It does not automatically increase this device's four drum controls.

## Configuration restore

Your existing Mac's preferences live in the macOS preferences system, outside Documents/Codex; deleting that folder does not itself remove them. Keep this export for a reinstall or another Mac.

With Python 3 installed, preview first:

```sh
python3 Configuration/restore-presets.py
```

To restore, quit **3£** and its **MIDI Touchbar** helper, then run:

```sh
python3 Configuration/restore-presets.py --apply
```

This replaces the matching saved layouts and assignments, retaining unrelated preferences. A timestamped `before-restore-*.plist` is written beside the script. To undo, quit the apps again and import that backup with `defaults import ch.uebe.MIDI-Touchbar /path/to/backup.plist`. No restore has been applied while creating this archive.

To configure manually instead, put a piano and four pads on a preset. Set each pad to Control Change, momentary, channel 1; number them 1, 2, 3, 4; set range 0–127. In Live enable the keyboard MIDI input and use the routing above.

## Preservation and validation

The `.amxd` and `.maxpat` are byte-for-byte copies of the recovered device. The rack and starter set have portable relative sample/device references; original-machine preset search paths were cleared. Six WAV samples are included. The original full song, vocals, and recording takes are not part of this reusable kit.

The saved project XML, references, configuration keys, and MIDI note counts were checked during packaging. The newly assembled starter still needs an interactive load/playback check in Ableton; hardware touch response and another Mac's installation are not verified by file checks. If Live asks to locate media, point its file manager at this extracted kit and Collect All and Save. The standalone MIDI files and editable device source provide an independent recovery route.

The provided rhythms and samples preserve this project's material; this archive does not grant additional rights to original song material or third-party components. The app and control-surface code remain in the parent repository.

Ableton reference: https://www.ableton.com/en/manual/live-concepts/
