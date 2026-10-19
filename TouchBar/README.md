# 3£ Touch Bar

The authoritative Mac app source is now in [`threee/`](threee/README.md): the original main app, MIDI bridge, supporting headers and resources recovered from iCloud, plus the integrated Ableton Record control.

The canonical installed app is `/Applications/3E.app`. Its MIDI branding is **3£**; its MIDI ports are **3£ Surface** and **3£ Keyboard**. Ableton's script loader requires a Python-compatible control-surface name: **_3E**. The `recovered/` bundle is the historical binary dependency/baseline for the original third-party MIDI engine and keeps its original archive name. Building does not install another app automatically.

Hold either edge arrow of a piano to expand that keyboard. The joined left-hand control contains Close, gesture mode, visible octaves, and a **harmony icon** for Roman-numeral scale degrees; it uses the selected preset's color and replaces preset-change arrows while expanded. The harmony icon is smaller than the other control icons, glows cyan with a status dot when enabled, and has no text label. Degree visibility is saved independently for each piano and follows Ableton's current root and scale without changing MIDI notes. Seven-note scales use major/minor/diminished/augmented triad notation (for example, C major: I, ii, iii, IV, V, vi, vii°); other scale sizes retain neutral degree labels. These are scale-derived triads, not detection of played chords or sevenths. In-scale black keys use a brighter cyan shade; white keys retain a lighter shade of the same color. Numerals align at the top of each key, including white keys' exposed upper stems, and are omitted where the key is too narrow to show them legibly.

In the normal MIDI layout, preset navigation sits directly beside the unchanged left-hand X, followed by the same 32-point Record control. In Control Surface Mode, the 76-point Loop control occupies that same left slot, keeping Record aligned; BPM and More follow it, with the native control surface on the far right. Record's tap, arm/disarm swipes, recording-only red indicator, and held transport/loop options are unchanged. Loop keeps tap-to-toggle and left/right Punch In/Out swipes.

Piano black-key hit boxes occupy only the upper half. The lower half is a continuous white-key lane, including beneath black keys, for white-only glissando. Upper-half touches still select black or white keys according to their horizontal position. This applies to compact, expanded and shifted keyboards in all gesture modes; it does not change drawing, notes, channels, or the edge-arrow controls.

`Strip3/`, `strip3-rebuild/`, `legacy-source/` and `record-companion/` are superseded reconstruction/test work. They are **not** the source of the current installed app and must not replace it. The original recovery is preserved in commit `355f072`; ongoing work uses `threee/`.

This public repository contains TouchBar and TouchTab in separate folders, plus the combined single-app edition. The Instagram/Facebook service remains in the separate private `Ezodis/instagram-grill-bot` repository. Private mixed-project history has not been copied here.

## Releases and updates

Official releases: https://github.com/Ezodis/3E/releases — use `touchbar-v…` releases / `TouchBar.zip`, not TouchTab assets.

The menu's **Automatically Install Updates** toggle defaults on. 3£ checks for the latest stable release for the installed edition (`touchbar-v…` or `combined-v…`) at launch and every six hours, then downloads and verifies the matching app automatically. It waits for 3£ and the MIDI helper to exit, replaces the app, and restarts it. Disable the toggle to require confirmation from **Check for Update…**. Updates are taken from this repository, not the Instagram repository or the MIDI engine vendor's old feed. The archive contains the canonical `3£.app`, including its MIDI engine and Ableton `_3E` script.
