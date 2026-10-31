# 3E Phone Bar for Ableton Live

3E installs `_3E_Phone_Bar` into existing Ableton User Libraries when Phone Bar
starts (including libraries relocated through Live's Library settings).
Restart Live after the first install, then select **3E Phone Bar** in a free
Control Surface row. Choose **3E Phone Bar** as Input, leave Output **None**, and
enable **Track** and **Remote** for the input. Keep the existing **3E** Touch Bar
surface in its own row.

On macOS, 3E creates the **3E Phone Bar** virtual MIDI source. On Windows, create
a loopMIDI port with that name and select it in both Phone Bar and Live.

Controls use MIDI channel 16. The piano defaults to channel 1 and may use
channels 1–15, so its notes cannot invoke control-surface commands. Select the
matching input/channel on an armed instrument track. Phone Bar does not insert
instruments, change track arming, or modify an existing Set when connected.

| Phone control | Live mapping |
| --- | --- |
| Mixer strips 1–8 | Tracks 1–8: volume, pan, Send A, mute, solo |
| Deck A / B | Tracks 1 / 2 |
| Launch | Existing clip in the selected scene; never records an empty slot |
| Stop | Stop the deck track's clips |
| Cue | Select the deck track and its clip slot |
| Crossfader | Main crossfader; assigns deck tracks to A / B when moved |
| JOG / FINE | Move a playing warped-audio or MIDI clip by 1/16 or 1/64 beat per tick |
| Loop | Toggle the loaded clip loop; halve/double it or set 1, 2, 4 or 8 clip bars |
| Scene pads | Launch existing clips in scenes 1–4 on the deck track |
| Low / Mid / High | EQ Three gains, when that effect is present on the deck |
| Filter | Auto Filter frequency, when that effect is present on the deck |

Mappings look up tracks/devices at gesture time, so they follow track reordering
and device changes. No MIDI output port is required. The surface writes a small local feedback snapshot
with current clip names, playback position, loop bounds and mixer parameters.
Phone Bar reads it at most four times a second and clears stale data. Audio-file
paths are never included. Restart Live once after updating the script.

Loop size controls use channel-16 notes 80/81 (halve A/B), 82/83 (double),
and 84–91 (1/2/4/8 bars, alternating A/B). Fine jog uses CC42/43; ordinary
jog keeps CC40/41. Unwarped audio and recording clips are protected from jog
and loop-length edits.

Run routing tests with `python3 Shared/PhoneControl/Ableton/test_mapping.py`.
