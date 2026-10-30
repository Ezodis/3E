#!/bin/zsh
set -eu
cd "${0:A:h}"
strip_repo="${PWD:h:h}"
strip_identity="${STRIP_SIGNING_IDENTITY:-EDA0E1C9F0DD46BE3437CD2733933E31D3A8623D}"
mkdir -p "$strip_repo/build/threee"
strip_edition="${1:---combined}"
case "$strip_edition" in
  --combined|--combined-main-only|--touchbar-only|--touchtab-only|--phone-only|--bridge-only) ;;
  *) printf 'Usage: build.sh [--combined | --touchbar-only | --combined-main-only | --bridge-only]\n' >&2; exit 2 ;;
esac
strip_combined=NO
if [[ "$strip_edition" == --combined || "$strip_edition" == --combined-main-only || "$strip_edition" == --touchtab-only ]]; then
  strip_combined=YES
  for strip_arch in arm64 x86_64; do
  xcrun swiftc -emit-library -O -target "$strip_arch-apple-macosx12.0" -module-name ThreeEGestureEngine \
    "$strip_repo/../TouchTab/Touch-Tab/AppSwitcher.swift" \
    "$strip_repo/../TouchTab/Touch-Tab/SwipeManager.swift" \
    "$strip_repo/../TouchTab/CombinedModule.swift" \
    -o "$strip_repo/build/threee/ThreeEGestureEngine-$strip_arch.dylib"
  done
  xcrun lipo -create "$strip_repo/build/threee/ThreeEGestureEngine-arm64.dylib" "$strip_repo/build/threee/ThreeEGestureEngine-x86_64.dylib" -output "$strip_repo/build/threee/ThreeEGestureEngine.dylib"
  codesign --force --sign - "$strip_repo/build/threee/ThreeEGestureEngine.dylib"
fi
strip_main_flags=(-DSTRIP_COMBINED_TOUCHTAB=1)
strip_minimum=12.0
if [[ "$strip_combined" == YES ]]; then strip_main_flags=(-DSTRIP_COMBINED_TOUCHTAB=1); strip_minimum=12.0; fi
if [[ "$strip_edition" == --combined-main-only ]]; then
  xcrun clang -arch arm64 -arch x86_64 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
    -mmacosx-version-min=12.0 "${strip_main_flags[@]}" -framework AppKit -framework Carbon \
    -framework ApplicationServices -framework QuartzCore -framework CoreImage -framework AVFoundation -framework CoreMedia -weak_framework ScreenCaptureKit main.m -o "$strip_repo/build/threee/ThreeECombinedMain"
  exit 0
fi
if [[ "$strip_edition" == --bridge-only ]]; then
  xcrun clang -arch arm64 -arch x86_64 -dynamiclib -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
    -mmacosx-version-min=11.0 -framework AppKit -framework CoreMIDI MidiBridge.m \
    -o "$strip_repo/build/threee/ThreeEMidiBridge.dylib"
  codesign --force --sign - "$strip_repo/build/threee/ThreeEMidiBridge.dylib"
  exit 0
fi
strip_stage=$(mktemp -d /tmp/strip3-build.XXXXXX)
trap '[[ "$strip_stage" == /tmp/strip3-build.* ]] && /bin/rm -r -- "$strip_stage"' EXIT
strip_app="$strip_stage/3E.app"
ditto --norsrc --noextattr "$strip_repo/recovered/Strip3£.app" "$strip_app"
cp Info.plist "$strip_app/Contents/Info.plist"
if [[ "$strip_combined" == YES ]]; then
  mkdir -p "$strip_app/Contents/Frameworks"
  cp "$strip_repo/build/threee/ThreeEGestureEngine.dylib" "$strip_app/Contents/Frameworks/"
  /usr/libexec/PlistBuddy -c 'Add ThreeEIncludesTouchTab bool true' "$strip_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set LSMinimumSystemVersion 12.0' "$strip_app/Contents/Info.plist"
fi
ditto --norsrc --noextattr Resources "$strip_app/Contents/Resources"
mkdir -p "$strip_app/Contents/Resources/Ableton/_3E"
cp "$strip_repo/threee/Ableton/_3E/"*.py "$strip_app/Contents/Resources/Ableton/_3E/"
xcrun clang -arch arm64 -arch x86_64 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
  -mmacosx-version-min="$strip_minimum" "${strip_main_flags[@]}" -framework AppKit -framework Carbon \
  -framework ApplicationServices -framework QuartzCore -framework CoreImage -framework AVFoundation -framework CoreMedia -weak_framework ScreenCaptureKit main.m -o "$strip_app/Contents/MacOS/ThreeE"
zsh "$strip_repo/../Shared/PhoneControl/MacHost/build-hosts.sh" "$strip_app"
strip_apps_helper="$strip_app/Contents/Helpers/ThreeE Apps.app"
cp "$strip_app/Contents/MacOS/ThreeE" "$strip_apps_helper/Contents/MacOS/ThreeEApps"
strip_midi="$strip_app/Contents/Helpers/MIDI Touchbar.app"
plutil -replace CFBundleName -string '3E' "$strip_midi/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string '3E' "$strip_midi/Contents/Info.plist"
# Replace every application icon inherited from the bundled helper apps.
for strip_icon in "$strip_app"/**/*.icns(N); do
  cp "$strip_repo/../Shared/Brand/3E.icns" "$strip_icon"
done
strip_framework="$strip_midi/Contents/Frameworks/SnoizeMIDI.framework"
[[ -e "$strip_framework/Versions/Current" ]] || ln -s A "$strip_framework/Versions/Current"
[[ -e "$strip_framework/SnoizeMIDI" ]] || ln -s Versions/Current/SnoizeMIDI "$strip_framework/SnoizeMIDI"
[[ -e "$strip_framework/Resources" ]] || ln -s Versions/Current/Resources "$strip_framework/Resources"
xcrun clang -arch arm64 -arch x86_64 -dynamiclib -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
  -mmacosx-version-min=11.0 -framework AppKit -framework ApplicationServices -framework CoreMIDI MidiBridge.m \
  -o "$strip_midi/Contents/Frameworks/ThreeEMidiBridge.dylib"
strip_modules=touchbar,touchtab,phone
case "$strip_edition" in
  --touchbar-only) strip_modules=touchbar ;;
  --touchtab-only) strip_modules=touchtab ;;
  --phone-only) strip_modules=phone ;;
esac
xattr -cr "$strip_app"
codesign --force --sign - "$strip_framework"
codesign --force --sign - "$strip_midi/Contents/Frameworks/ThreeEMidiBridge.dylib"
codesign --force --sign - "$strip_midi"
codesign --force --sign - "$strip_apps_helper"
STRIP_SIGNING_IDENTITY="$strip_identity" zsh Resources/ConfigureModules.sh "$strip_app" "$strip_modules"
codesign --verify --deep --strict "$strip_app"
strip_output="$strip_repo/build/threee/3E.app"
if [[ -e "$strip_output" ]]; then
  [[ -f "$strip_output/Contents/Info.plist" && -f "$strip_output/Contents/MacOS/ThreeE" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$strip_output/Contents/Info.plist")" == local.musicstrip.app ]]
  /bin/rm -r -- "$strip_output" # Only this verified generated build artifact.
fi
ditto --norsrc --noextattr "$strip_app" "$strip_output"
codesign --verify --deep --strict "$strip_output"
printf 'Built and verified: %s\n' "$strip_repo/build/threee/3E.app"
# No installation, launch, zip or persistent backup happens automatically.
