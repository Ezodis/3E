# 3E

The **3E base app includes all modules available for its platform**: install **3E Combined** on macOS or **3£Windows** on Windows. Modules can be enabled or used independently from the same menu. Smaller standalone editions are optional alternatives; Phone Bar is already included in the base app.

| App | Source | Purpose |
| --- | --- | --- |
| 3£Windows | [Windows](Windows/) · [portable installer](3%C2%A3Windows.ps1) | One Windows tray menu for drag, Clicks keyboard, PowerToys, optional iPhone trackpad, auto dark and wallpaper |
| 3E Combined (Mac base app) | [TouchBar](TouchBar/) + [TouchTab](TouchTab/CombinedModule.swift) + [Phone Bar](Shared/PhoneControl/) | All three modules in one installed app and one menu-bar icon |
| TouchBar (3E) | [TouchBar](TouchBar/) | Custom Touch Bar MIDI keyboards, Ableton live-performance controls, app/window and media control |
| TouchTab | [TouchTab](TouchTab/) | Four-finger trackpad app switching, pinch copy/paste and force-click window switching |

Windows setup and releases now live here, moved from `Ezodis/eduu`. Download **3£Windows.ps1** from a [`windows-v…` release](https://github.com/Ezodis/3E/releases) and copy that single file to another Windows PC. Missing third-party dependencies require internet and administrator approval. See [Windows installation, controls and update details](Windows/README.md).

## Phone Bar module

Windows and macOS use one [shared phone interface and receiver](Shared/PhoneControl/README.md): reconnecting Wi-Fi trackpad, double-tap dragging, four-finger desktop gestures, Apps hold/swipe switching, and a Media button that opens two decks or an eight-track MIDI mixer. Knobs support vertical and circular dragging. Ableton performs the audio mixing through your MIDI mappings.

Windows always bundles the [Phone Bar module](Windows/PhoneBar/) and shared receiver. On Mac, **3E → Phone Bar** provides pairing, copying the Watch link and stopping the receiver. The base app embeds the module, so a separate Phone app is unnecessary. The optional standalone **3E Phone.app** uses the same module and can be built with `zsh Shared/PhoneControl/MacHost/build-app.sh`. The phone feature requires macOS 14+ and bundles its runtime; older supported systems retain the other modules. If Touch Bar interfaces are unavailable, the base app retains a menu for Phone Bar and TouchTab. Feature-branch builds appear as **3E-Combined-Mac** and **3E-Phone-Mac** artifacts in the [phone workflow](.github/workflows/phone-control.yml), independently of published releases.

Included does not mean automatically running: Phone Bar starts only when selected and has its own stop/cleanup lifecycle. Windows' keyboard, shortcuts, themes and wallpaper retain their independent toggles. Platform-specific hardware and permissions still apply. There is no separate plugin download or duplicate copy of the phone web interface to keep updated.

## Downloads

Get the current **Combined**, **TouchBar only**, or **TouchTab only** download from [Releases](https://github.com/Ezodis/3E/releases). Each is a universal Intel/Apple Silicon build; see hardware and permission requirements below. The app's update check selects the newest version for its own edition.

Every push to `main` runs [the release workflow](.github/workflows/releases.yml). **All modules (3E Combined, TouchBar, TouchTab and 3£Windows) share one version line**: base version in [release-versions.json](release-versions.json) plus the workflow run number. Only modules whose source changed since their own last release are rebuilt and published, and they take that run's version; unchanged modules keep the version they last shipped with. Because TouchTab and Phone Bar are embedded in the Combined base app, a TouchTab change also releases Combined, and a `Shared/` change releases Combined, TouchBar and 3£Windows. Editing `release-versions.json` counts as a change to every module and re-syncs them all to one version. All updated Mac editions must build before any is published. Releases are immutable versioned downloads with SHA-256 checksums and source-commit metadata. Later builds always have higher versions, so existing update checks recognize them. A failed build leaves the last working release intact; inspect the [Actions page](https://github.com/Ezodis/3E/actions) rather than assuming unpublished source is already downloadable. Manual reruns recover drafts but never overwrite a published version.

CI builds are ad-hoc signed and are not notarized; users must approve their downloaded app on their own Mac. Local release builds can use the configured development signing certificate. Automation never modifies the installed `/Applications/3E.app` or personal permissions/presets.

Download the true single-app combined edition or individual apps from [Releases](https://github.com/Ezodis/3E/releases). The older `bundle-v1.0.0` archive contains two separate apps; it is not the integrated edition.

- `touchbar-v…`: `TouchBar.zip`, containing `3E.app`.
- `touchtab-v…`: `TouchTab.zip`, containing `Touch-Tab.app`.
- `combined-v…`: `3E-Combined.zip`, containing only `3E.app` with TouchTab's gesture engine embedded in the main process.
- `bundle-v…`: `3E-Mac-Apps.zip`, containing both apps.

Each edition checks only its own release prefix. A combined update cannot accidentally install the TouchBar-only or TouchTab-only edition. Update checks offer downloads; they do not silently replace running apps. Existing legacy tags are retained for historical reference.

## Single-app edition

Install `3E.app` from a `combined-v…` release. Its existing 3E menu contains **Touch Tab**; toggle this to enable/disable the trackpad engine. The combined edition has one app installation and no separate TouchTab process or icon. The gesture engine runs directly inside the main 3E process and uses that process's Accessibility approval. Other macOS permission categories (such as Automation for media apps) remain separate. No permissions are granted or reset by the installer. The app retains its bundle identifier, signing identity and preferences across the rename.

Four-finger left/right switches applications; four-finger pinch in/out copies/pastes; force-click switches windows in the active app (Command + force-click reverses direction). Direct Touch Bar piano touches are excluded. Quit stops the gesture tap, pressure monitor and existing internal helpers. Do not also run standalone TouchTab, or gestures could execute twice.

Build from the repo root: `zsh TouchBar/threee/Source/build.sh`. The default is the full Combined base app; `--combined` remains an explicit alias, and `--touchbar-only` builds the smaller edition. On the development Mac, quit 3E and use `zsh TouchBar/threee/install-combined.sh` to install the exact verified combined build at `/Applications/3E.app`. Source and build outputs use `threee`, and executable/helper names use `ThreeE`; the legacy internal bundle and preference identifiers remain stable to preserve settings and permissions. The combined edition requires macOS 12+. Physical gestures should be tested on the intended trackpad; automated tests do not synthesize app-switching keystrokes. Packaging verifies the gesture engine, MIDI helper and both architectures of Phone Bar before accepting a base release.

## Development and provenance

### Compatibility

Version 3.0.11 builds TouchBar and Combined as universal Intel/Apple Silicon binaries. Combined requires macOS 12+, TouchBar requires macOS 11+, and standalone TouchTab requires macOS 12+. TouchBar features require a physical Touch Bar; TouchTab requires a multitouch trackpad, with force-click requiring compatible hardware. These apps cannot provide physical Touch Bar controls on Macs without that hardware. Intel is cross-built but has not been physically tested here.

Downloads are development-signed, not Developer ID notarized. Another Mac may require manual Gatekeeper approval and its own Accessibility/Automation permissions. Four-finger macOS desktop gestures may conflict with TouchTab. Choose either the combined edition or the standalone apps, not both gesture engines simultaneously. There are no runtime dependencies on `/Users/3du/Documents/Codex`.

Read each app's README for its build and permissions requirements. TouchBar preserves the recovered original engine alongside maintained source; its additive installer preserves the working installed engine. TouchTab was imported from [Ezodis/Touch-Tab](https://github.com/Ezodis/Touch-Tab), originally [ris58h/Touch-Tab](https://github.com/ris58h/Touch-Tab). Original copyright notices and source history remain in those repositories. This repository reorganization does not grant new licenses for upstream components.

Standalone apps retain independent settings and permissions. In the combined edition, the new gesture preference lives under 3E; existing piano layouts, MIDI mappings and media/app settings remain unchanged. No Instagram bot files belong in this repository.
