# 3E

Two independent macOS apps. Install either app or both; neither requires the other.

| App | Source | Purpose |
| --- | --- | --- |
| TouchBar (3£) | [TouchBar](TouchBar/) | Custom Touch Bar MIDI keyboards, Ableton live-performance controls, app/window and media control |
| TouchTab | [TouchTab](TouchTab/) | Four-finger trackpad app switching, pinch copy/paste and force-click window switching |

## Downloads

Download individual apps or the combined archive from [Releases](https://github.com/Ezodis/3E/releases). The combined archive contains two separate apps, not a replacement or merged application.

- `touchbar-v…`: `TouchBar.zip`, containing `Strip3£.app`.
- `touchtab-v…`: `TouchTab.zip`, containing `Touch-Tab.app`.
- `bundle-v…`: `3E-Mac-Apps.zip`, containing both apps.

Each app checks only its own release prefix. Update checks offer downloads; they do not silently replace running apps. Existing legacy TouchBar tags are retained for historical reference.

## Development and provenance

Read each app's README for its build and permissions requirements. TouchBar preserves the recovered original engine alongside maintained source; its additive installer preserves the working installed engine. TouchTab was imported from [Ezodis/Touch-Tab](https://github.com/Ezodis/Touch-Tab), originally [ris58h/Touch-Tab](https://github.com/ris58h/Touch-Tab). Original copyright notices and source history remain in those repositories. This repository reorganization does not grant new licenses for upstream components.

The apps remain independent processes with independent settings and permissions. No Instagram bot files belong in this repository.
