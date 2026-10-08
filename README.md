# 3E

Choose one combined macOS app, or either app individually.

| App | Source | Purpose |
| --- | --- | --- |
| 3£ Combined | [TouchBar](TouchBar/) + [TouchTab gesture module](TouchTab/CombinedModule.swift) | Both feature sets in one installed app and one menu-bar icon |
| TouchBar (3£) | [TouchBar](TouchBar/) | Custom Touch Bar MIDI keyboards, Ableton live-performance controls, app/window and media control |
| TouchTab | [TouchTab](TouchTab/) | Four-finger trackpad app switching, pinch copy/paste and force-click window switching |

## Downloads

Current downloads: [3£ Combined 3.0.9](https://github.com/Ezodis/3E/releases/download/combined-v3.0.9/3E-Combined.zip), [TouchBar only 3.0.9](https://github.com/Ezodis/3E/releases/download/touchbar-v3.0.9/TouchBar.zip), or [TouchTab only 1.5.2](https://github.com/Ezodis/3E/releases/download/touchtab-v1.5.2/TouchTab.zip). Each is a universal Intel/Apple Silicon build; see hardware and permission requirements below.

Download the true single-app combined edition or individual apps from [Releases](https://github.com/Ezodis/3E/releases). The older `bundle-v1.0.0` archive contains two separate apps; it is not the integrated edition.

- `touchbar-v…`: `TouchBar.zip`, containing `Strip3£.app`.
- `touchtab-v…`: `TouchTab.zip`, containing `Touch-Tab.app`.
- `combined-v…`: `3E-Combined.zip`, containing only `Strip3£.app` with TouchTab's gesture engine embedded in the main process.
- `bundle-v…`: `3E-Mac-Apps.zip`, containing both apps.

Each edition checks only its own release prefix. A combined update cannot accidentally install the TouchBar-only or TouchTab-only edition. Update checks offer downloads; they do not silently replace running apps. Existing legacy tags are retained for historical reference.

## Single-app edition

Install `Strip3£.app` from a `combined-v…` release. Its existing 3£ menu contains **Touch Tab**; toggle this to enable/disable the trackpad engine. The combined edition has one app installation and no separate TouchTab process or icon. The gesture engine runs directly inside the main 3£ process and uses that process's Accessibility approval. Other macOS permission categories (such as Automation for media apps) remain separate. No permissions are granted or reset by the installer.

Four-finger left/right switches applications; four-finger pinch in/out copies/pastes; force-click switches windows in the active app (Command + force-click reverses direction). Direct Touch Bar piano touches are excluded. Quit stops the gesture tap, pressure monitor and existing internal helpers. Do not also run standalone TouchTab, or gestures could execute twice.

Build from the repo root: `zsh TouchBar/musicstrip/Source/build.sh --combined`. Without that flag, the existing build remains TouchBar-only. On the development Mac, quit 3£ and use `zsh TouchBar/musicstrip/install-combined.sh` to update the canonical app in place while retaining the original MIDI engine and installed app-picker helper. The combined edition requires macOS 12+. Physical gestures should be tested on the intended trackpad; automated tests do not synthesize app-switching keystrokes.

## Development and provenance

### Compatibility

Version 3.0.9 builds TouchBar and Combined as universal Intel/Apple Silicon binaries. Combined requires macOS 12+, TouchBar requires macOS 11+, and standalone TouchTab requires macOS 12+. TouchBar features require a physical Touch Bar; TouchTab requires a multitouch trackpad, with force-click requiring compatible hardware. These apps cannot provide physical Touch Bar controls on Macs without that hardware. Intel is cross-built but has not been physically tested here.

Downloads are development-signed, not Developer ID notarized. Another Mac may require manual Gatekeeper approval and its own Accessibility/Automation permissions. Four-finger macOS desktop gestures may conflict with TouchTab. Choose either the combined edition or the standalone apps, not both gesture engines simultaneously. There are no runtime dependencies on `/Users/3du/Documents/Codex`.

Read each app's README for its build and permissions requirements. TouchBar preserves the recovered original engine alongside maintained source; its additive installer preserves the working installed engine. TouchTab was imported from [Ezodis/Touch-Tab](https://github.com/Ezodis/Touch-Tab), originally [ris58h/Touch-Tab](https://github.com/ris58h/Touch-Tab). Original copyright notices and source history remain in those repositories. This repository reorganization does not grant new licenses for upstream components.

Standalone apps retain independent settings and permissions. In the combined edition, the new gesture preference lives under 3£; existing piano layouts, MIDI mappings and media/app settings remain unchanged. No Instagram bot files belong in this repository.
