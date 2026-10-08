#!/bin/zsh
set -eu
cd "${0:A:h}"
strip_repo="${PWD:h:h}"
strip_identity="${STRIP_SIGNING_IDENTITY:-EDA0E1C9F0DD46BE3437CD2733933E31D3A8623D}"
mkdir -p "$strip_repo/build/musicstrip"
strip_combined=NO
if [[ "${1:-}" == --combined || "${1:-}" == --combined-main-only ]]; then
  strip_combined=YES
  xcrun swiftc -emit-library -O -target "$(uname -m)-apple-macosx12.0" -module-name ThreeEGestureEngine \
    "$strip_repo/../TouchTab/Touch-Tab/AppSwitcher.swift" \
    "$strip_repo/../TouchTab/Touch-Tab/SwipeManager.swift" \
    "$strip_repo/../TouchTab/CombinedModule.swift" \
    -o "$strip_repo/build/musicstrip/ThreeEGestureEngine.dylib"
  codesign --force --sign - "$strip_repo/build/musicstrip/ThreeEGestureEngine.dylib"
fi
strip_main_flags=()
strip_minimum=11.0
if [[ "$strip_combined" == YES ]]; then strip_main_flags=(-DSTRIP_COMBINED_TOUCHTAB=1); strip_minimum=12.0; fi
if [[ "${1:-}" == --combined-main-only ]]; then
  xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
    -mmacosx-version-min=12.0 "${strip_main_flags[@]}" -framework AppKit -framework Carbon \
    -framework ApplicationServices -framework QuartzCore main.m -o "$strip_repo/build/musicstrip/MusicStripCombinedMain"
  exit 0
fi
if [[ "${1:-}" == --bridge-only ]]; then
  xcrun clang -dynamiclib -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
    -mmacosx-version-min=11.0 -framework AppKit -framework CoreMIDI MidiBridge.m \
    -o "$strip_repo/build/musicstrip/MusicStripMidiBridge.dylib"
  codesign --force --sign - "$strip_repo/build/musicstrip/MusicStripMidiBridge.dylib"
  exit 0
fi
strip_stage=$(mktemp -d /tmp/strip3-build.XXXXXX)
trap '[[ "$strip_stage" == /tmp/strip3-build.* ]] && /bin/rm -r -- "$strip_stage"' EXIT
strip_app="$strip_stage/Strip3£.app"
ditto --norsrc --noextattr "$strip_repo/recovered/Strip3£.app" "$strip_app"
cp Info.plist "$strip_app/Contents/Info.plist"
if [[ "$strip_combined" == YES ]]; then
  mkdir -p "$strip_app/Contents/Frameworks"
  cp "$strip_repo/build/musicstrip/ThreeEGestureEngine.dylib" "$strip_app/Contents/Frameworks/"
  /usr/libexec/PlistBuddy -c 'Add ThreeEIncludesTouchTab bool true' "$strip_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set LSMinimumSystemVersion 12.0' "$strip_app/Contents/Info.plist"
fi
ditto --norsrc --noextattr Resources "$strip_app/Contents/Resources"
mkdir -p "$strip_app/Contents/Resources/Ableton/_3E"
cp "$strip_repo/musicstrip/Ableton/_3E/"*.py "$strip_app/Contents/Resources/Ableton/_3E/"
xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
  -mmacosx-version-min="$strip_minimum" "${strip_main_flags[@]}" -framework AppKit -framework Carbon \
  -framework ApplicationServices -framework QuartzCore main.m -o "$strip_app/Contents/MacOS/MusicStrip"
strip_apps_helper="$strip_app/Contents/Helpers/MusicStrip Apps.app"
cp "$strip_app/Contents/MacOS/MusicStrip" "$strip_apps_helper/Contents/MacOS/MusicStripApps"
strip_midi="$strip_app/Contents/Helpers/MIDI Touchbar.app"
strip_framework="$strip_midi/Contents/Frameworks/SnoizeMIDI.framework"
[[ -e "$strip_framework/Versions/Current" ]] || ln -s A "$strip_framework/Versions/Current"
[[ -e "$strip_framework/SnoizeMIDI" ]] || ln -s Versions/Current/SnoizeMIDI "$strip_framework/SnoizeMIDI"
[[ -e "$strip_framework/Resources" ]] || ln -s Versions/Current/Resources "$strip_framework/Resources"
xcrun clang -dynamiclib -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
  -mmacosx-version-min=11.0 -framework AppKit -framework CoreMIDI MidiBridge.m \
  -o "$strip_midi/Contents/Frameworks/MusicStripMidiBridge.dylib"
xattr -cr "$strip_app"
codesign --force --sign - "$strip_framework"
codesign --force --sign - "$strip_midi/Contents/Frameworks/MusicStripMidiBridge.dylib"
codesign --force --sign - "$strip_midi"
codesign --force --sign - "$strip_apps_helper"
codesign --force --sign "$strip_identity" --timestamp=none "$strip_app"
codesign --verify --deep --strict "$strip_app"
strip_output="$strip_repo/build/musicstrip/Strip3£.app"
if [[ -e "$strip_output" ]]; then
  [[ -f "$strip_output/Contents/Info.plist" && -f "$strip_output/Contents/MacOS/MusicStrip" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$strip_output/Contents/Info.plist")" == local.musicstrip.app ]]
  /bin/rm -r -- "$strip_output" # Only this verified generated build artifact.
fi
ditto --norsrc --noextattr "$strip_app" "$strip_output"
codesign --verify --deep --strict "$strip_output"
printf 'Built and verified: %s\n' "$strip_repo/build/musicstrip/Strip3£.app"
# No installation, launch, zip or persistent backup happens automatically.
