# 3£ Touch Bar

The authoritative Mac app source is now in [`musicstrip/`](musicstrip/README.md): the original main app, MIDI bridge, supporting headers and resources recovered from iCloud, plus the integrated Ableton Record control.

The canonical installed app is `/Applications/3£.app`. Its MIDI branding is **3£**; its MIDI ports are **3£ Surface** and **3£ Keyboard**. Ableton's script loader requires a Python-compatible control-surface name: **_3E**. The `recovered/` bundle is the historical binary dependency/baseline for the original third-party MIDI engine and keeps its original archive name. Building does not install another app automatically.

`Strip3/`, `strip3-rebuild/`, `legacy-source/` and `record-companion/` are superseded reconstruction/test work. They are **not** the source of the current installed app and must not replace it. The original recovery is preserved in commit `355f072`; ongoing work uses `musicstrip/`.

This public repository contains TouchBar and TouchTab in separate folders, plus the combined single-app edition. The Instagram/Facebook service remains in the separate private `Ezodis/instagram-grill-bot` repository. Private mixed-project history has not been copied here.

## Releases and updates

Official releases: https://github.com/Ezodis/3E/releases — use `touchbar-v…` releases / `TouchBar.zip`, not TouchTab assets.

Both **Check for Update…** and **Check for Update on launch** select this repository's latest stable release for the installed edition (`touchbar-v…` or `combined-v…`), not the Instagram repository or the MIDI engine vendor's old feed. Downloading an update requires confirmation; checks never replace the running app or interrupt Ableton. The release archive contains the canonical `3£.app`, including its MIDI engine and Ableton `_3E` script.
