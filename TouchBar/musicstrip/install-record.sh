#!/bin/zsh
# Additive update of the canonical app: never replaces its working main/engine.
set -eu
cd "${0:A:h:h}"
strip_app='/Applications/Strip3£.app'
strip_helper="$strip_app/Contents/Helpers/MIDI Touchbar.app"
strip_framework="$strip_helper/Contents/Frameworks/SnoizeMIDI.framework"
strip_identity="${STRIP_SIGNING_IDENTITY:-EDA0E1C9F0DD46BE3437CD2733933E31D3A8623D}"
if pgrep -x MusicStrip >/dev/null || pgrep -x 'MIDI Touchbar' >/dev/null; then
  printf 'Quit Strip3 from its menu first. No files changed.\n' >&2
  exit 1
fi
[[ -f "$strip_app/Contents/MacOS/MusicStrip" ]]
zsh musicstrip/Source/build.sh --bridge-only
cp build/musicstrip/MusicStripMidiBridge.dylib "$strip_helper/Contents/Frameworks/MusicStripMidiBridge.dylib"
cp musicstrip/Source/Info.plist "$strip_app/Contents/Info.plist"
[[ -e "$strip_framework/Versions/Current" ]] || ln -s A "$strip_framework/Versions/Current"
[[ -e "$strip_framework/SnoizeMIDI" ]] || ln -s Versions/Current/SnoizeMIDI "$strip_framework/SnoizeMIDI"
[[ -e "$strip_framework/Resources" ]] || ln -s Versions/Current/Resources "$strip_framework/Resources"
mkdir -p "$strip_app/Contents/Resources/Ableton/_3E"
cp 'musicstrip/Ableton/_3E/'*.py "$strip_app/Contents/Resources/Ableton/_3E/"
strip_user_script="${STRIP_ABLETON_SCRIPT_DIR:-$HOME/Music/Ableton/User Library/Remote Scripts/_3E}"
mkdir -p "$strip_user_script"
cp 'musicstrip/Ableton/_3E/'*.py "$strip_user_script/"
codesign --force --sign - "$strip_framework"
codesign --force --sign - "$strip_helper"
codesign --force --sign "$strip_identity" --timestamp=none "$strip_app"
codesign --verify --deep --strict "$strip_app"
printf 'Updated canonical Strip3 Record bridge. No main/engine replacement or backup created.\n'
