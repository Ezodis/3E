#!/bin/zsh
# Update the existing app in place; keep the original MIDI engine/resources.
set -eu
cd "${0:A:h:h}"
zsh musicstrip/rename-installed.sh
strip_app='/Applications/3£.app'
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$strip_app/Contents/Info.plist")" == local.musicstrip.app ]]
if pgrep -x MusicStrip >/dev/null || pgrep -x 'MIDI Touchbar' >/dev/null; then
  printf 'Quit 3£ first. No installed files changed.\n' >&2; exit 1
fi
zsh musicstrip/Source/build.sh --combined-main-only
build/musicstrip/MusicStripCombinedMain --self-test
zsh musicstrip/install-record.sh
mkdir -p "$strip_app/Contents/Frameworks"
cp build/musicstrip/ThreeEGestureEngine.dylib "$strip_app/Contents/Frameworks/"
cp build/musicstrip/MusicStripCombinedMain "$strip_app/Contents/MacOS/MusicStrip"
if /usr/libexec/PlistBuddy -c 'Print ThreeEIncludesTouchTab' "$strip_app/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c 'Set ThreeEIncludesTouchTab true' "$strip_app/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c 'Add ThreeEIncludesTouchTab bool true' "$strip_app/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c 'Set LSMinimumSystemVersion 12.0' "$strip_app/Contents/Info.plist"
codesign --force --sign "${STRIP_SIGNING_IDENTITY:-EDA0E1C9F0DD46BE3437CD2733933E31D3A8623D}" --timestamp=none "$strip_app"
codesign --verify --deep --strict "$strip_app"
printf 'Combined 3£ installed in place. No standalone TouchTab process is launched.\n'
