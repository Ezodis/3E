# 3£

The **3£ base app includes all modules available for its platform**: install **3E Combined** on macOS or **3£** on Windows. Modules can be enabled or used independently from the same menu. Smaller downloads contain the same `3E.app` with only the selected modules installed. Click a missing feature in the menu to install it; the small gear menu can uninstall individual modules without deleting settings.

| App | Source | Purpose |
| --- | --- | --- |
| 3£ (Windows) | [Windows](Windows/) · [portable installer](3%C2%A3Windows.ps1) | One Windows tray menu for drag, Clicks keyboard, PowerToys, optional iPhone trackpad, auto dark and wallpaper |
| 3E Combined (Mac base app) | [TouchBar](TouchBar/) + [TouchTab](TouchTab/CombinedModule.swift) + [Phone Bar](Shared/PhoneControl/) | All three modules in one installed app and one menu-bar icon |
| TouchBar (3E) | [TouchBar](TouchBar/) | Custom Touch Bar MIDI keyboards, Ableton live-performance controls, app/window and media control |
| TouchTab | [TouchTab](TouchTab/) | Four-finger trackpad app switching, pinch copy/paste and force-click window switching |

Windows setup and releases now live here, moved from `Ezodis/eduu`. Download **3£Windows.ps1** from a [`windows-v…` release](https://github.com/Ezodis/3E/releases) and copy that single file to another Windows PC. Missing third-party dependencies require internet and administrator approval. See [Windows installation, controls and update details](Windows/README.md).

## Phone Bar module

Windows and macOS use one [shared phone interface and receiver](Shared/PhoneControl/README.md): reconnecting Wi-Fi trackpad, double-tap dragging, four-finger desktop gestures, Apps hold/swipe switching, and a Media button that opens two decks or an eight-track MIDI mixer. Knobs support vertical and circular dragging. Ableton performs the audio mixing through your MIDI mappings.

Windows always bundles the [Phone Bar module](Windows/PhoneBar/) and shared receiver. On Mac, **3E → Phone Bar** provides pairing, copying the Watch link and stopping the receiver. The base app embeds the module, so a separate Phone app is unnecessary. The Phone Bar-only download also contains **3E.app** and can be built with `zsh Shared/PhoneControl/MacHost/build-app.sh`. The phone feature requires macOS 14+ and bundles its runtime; older supported systems retain the other modules. If Touch Bar interfaces are unavailable, the base app retains a menu for Phone Bar and TouchTab. Feature-branch builds appear as **3E-Combined-Mac** and **3E-Phone-Mac** artifacts in the [phone workflow](.github/workflows/phone-control.yml), independently of published releases.

Included does not mean automatically running: Phone Bar starts only when selected and has its own stop/cleanup lifecycle. Windows' keyboard, shortcuts, themes and wallpaper retain their independent toggles. Platform-specific hardware and permissions still apply. There is no separate plugin download or duplicate copy of the phone web interface to keep updated.

## Car View (Mac)

Click **Car View** in the 3£ menu for larger controls and a large neon-outlined pointer. The small reverse-arrows button at the right of the same row toggles mirroring. There is no separate control panel. Car View temporarily selects a lower logical resolution on the main display; turning it off restores the original mode. It also turns off on main-display changes, sleep or session locking. The display change is scoped to the app so macOS restores it if the process exits unexpectedly.

**Mirror for Window Reflection** flips the live main display horizontally, including the neon pointer. Look at the reflected image in glass: physical mouse, Mac trackpad and Phone Bar gestures retain their normal directions and click coordinates. Mirror requires macOS 12.3+ and Screen Recording access for 3£. Frames stay on the Mac; this view does not record or transmit the desktop. **⌃⌥⌘0** exits Car View and restores the display size. Car View starts off on every launch.

## Downloads

Get the current **Combined**, **TouchBar only**, or **TouchTab only** download from [Releases](https://github.com/Ezodis/3E/releases). Each is a universal Intel/Apple Silicon build; see hardware and permission requirements below. Current Mac installs use the Combined update feed and preserve their module selection.

Every push to `main` runs [the release workflow](.github/workflows/releases.yml). **All modules (3E Combined, TouchBar, TouchTab and 3£Windows) share one version line**: base version in [release-versions.json](release-versions.json) plus the workflow run number. Mac downloads share the same host, so host/module changes rebuild every Mac selection. Only platform releases whose source changed since their own last release are rebuilt and published, and they take that run's version; unchanged modules keep the version they last shipped with. Because TouchTab and Phone Bar are embedded in the Combined base app, a TouchTab change also releases Combined, and a `Shared/` change releases Combined, TouchBar and 3£Windows. Editing `release-versions.json` counts as a change to every module and re-syncs them all to one version. All updated Mac editions must build before any is published. Releases are immutable versioned downloads with SHA-256 checksums and source-commit metadata. Later builds always have higher versions, so existing update checks recognize them. A failed build leaves the last working release intact; inspect the [Actions page](https://github.com/Ezodis/3E/actions) rather than assuming unpublished source is already downloadable. Manual reruns recover drafts but never overwrite a published version.

CI builds are ad-hoc signed and are not notarized; users must approve their downloaded app on their own Mac. Local release builds can use the configured development signing certificate. Automation never modifies the installed `/Applications/3E.app` or personal permissions/presets.

Every current Mac download contains **3E.app**, with the same bundle identifier and preferences:

- `combined-v…`: `3E-Combined.zip` starts with Touch Bar, Touch Tab and Phone Bar.
- `touchbar-v…`: `TouchBar.zip` starts with Touch Bar only.
- `touchtab-v…`: `TouchTab.zip` starts with Touch Tab only.
- `phone-v…`: `3E-Phone-Mac.zip` starts with Phone Bar only.

Click **Install…** beside an absent feature in the 3E menu. The gear menu installs or uninstalls modules; changing modules restarts 3E. Uninstalling removes the payload from the app, but preserves preferences. Module installation and automatic updates currently download the verified Combined archive, retain only the chosen modules in a staged app, verify its signature, then replace the existing app with rollback on failure. No second app is installed. Updates preserve the selected modules, even if all modules have been removed. A missing connection or incompatible release leaves the current app intact.

Older `Touch-Tab.app`, `3E Phone.app` and `bundle-v…` downloads are legacy applications. Quit those before migrating to `/Applications/3E.app`; their old standalone preferences are separate. Internal MIDI and Apps helper bundles remain inside 3E for compatibility with the recovered engine. The repository's `TouchBar/build/threee/3E.app` is a generated build artifact; install it at `/Applications/3E.app`. Normal launches prevent a second 3E instance from running.

## Single-app edition

Install `3E.app` from a `combined-v…` release. Its existing 3E menu contains **Touch Tab**; toggle this to enable/disable the trackpad engine. The combined edition has one app installation and no separate TouchTab process or icon. The gesture engine runs directly inside the main 3E process and uses that process's Accessibility approval. Other macOS permission categories (such as Automation for media apps) remain separate. No permissions are granted or reset by the installer. The app retains its bundle identifier, signing identity and preferences across the rename.

Four-finger left/right switches applications; four-finger pinch in/out copies/pastes; force-click switches windows in the active app (Command + force-click reverses direction). Direct Touch Bar piano touches are excluded. Quit stops the gesture tap, pressure monitor and existing internal helpers. Do not also run standalone TouchTab, or gestures could execute twice.

Build from the repo root: `zsh TouchBar/threee/Source/build.sh`. The default is the full Combined base app; `--combined` remains an explicit alias, and `--touchbar-only`, `--touchtab-only` and `--phone-only` build smaller initial selections. On the development Mac, quit 3E and use `zsh TouchBar/threee/install-combined.sh` to install the exact verified combined build at `/Applications/3E.app`. Source and build outputs use `threee`, and executable/helper names use `ThreeE`; the legacy internal bundle and preference identifiers remain stable to preserve settings and permissions. The combined edition requires macOS 12+. Physical gestures should be tested on the intended trackpad; automated tests do not synthesize app-switching keystrokes. Packaging verifies the gesture engine, MIDI helper and both architectures of Phone Bar before accepting a base release.

## Development and provenance

### Compatibility

Version 3.0.11 builds TouchBar and Combined as universal Intel/Apple Silicon binaries. All current Mac downloads require macOS 12+; Phone Bar requires macOS 14+. TouchBar features require a physical Touch Bar; TouchTab requires a multitouch trackpad, with force-click requiring compatible hardware. These apps cannot provide physical Touch Bar controls on Macs without that hardware. Intel is cross-built but has not been physically tested here.

Downloads are development-signed, not Developer ID notarized. Another Mac may require manual Gatekeeper approval and its own Accessibility/Automation permissions. Four-finger macOS desktop gestures may conflict with TouchTab. Choose either the combined edition or the standalone apps, not both gesture engines simultaneously. There are no runtime dependencies on `/Users/3du/Documents/Codex`.

Read each app's README for its build and permissions requirements. TouchBar preserves the recovered original engine alongside maintained source; its additive installer preserves the working installed engine. TouchTab was imported from [Ezodis/Touch-Tab](https://github.com/Ezodis/Touch-Tab), originally [ris58h/Touch-Tab](https://github.com/ris58h/Touch-Tab). Original copyright notices and source history remain in those repositories. This repository reorganization does not grant new licenses for upstream components.

Standalone apps retain independent settings and permissions. In the combined edition, the new gesture preference lives under 3E; existing piano layouts, MIDI mappings and media/app settings remain unchanged. No Instagram bot files belong in this repository.
