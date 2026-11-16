#!/bin/zsh
# Builds the universal (arm64 + x86_64) "3£ Mouse.app" helper (gaming-mouse settings) at the given path.
# Called by TouchBar/threee/Source/build.sh; nothing is installed or launched.
set -eu
cd "${0:A:h}"
mouse_app="$1"
swift build -c release --arch arm64 --arch x86_64
mouse_bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
/bin/rm -rf -- "$mouse_app"
mkdir -p "$mouse_app/Contents/MacOS" "$mouse_app/Contents/Resources"
cp "$mouse_bin/ThreeEMouse" "$mouse_app/Contents/MacOS/ThreeEMouse"
cp "$mouse_bin/mousectl" "$mouse_app/Contents/Resources/mousectl"
cp Info.plist "$mouse_app/Contents/Info.plist"
cp ../../../Shared/Brand/3E.icns "$mouse_app/Contents/Resources/3E.icns"
cp ../../../Shared/PC205/PROTOCOL.md "$mouse_app/Contents/Resources/PROTOCOL.md"
xcrun lipo -archs "$mouse_app/Contents/MacOS/ThreeEMouse" | /usr/bin/grep -q arm64
xcrun lipo -archs "$mouse_app/Contents/MacOS/ThreeEMouse" | /usr/bin/grep -q x86_64
codesign --force --sign - "$mouse_app/Contents/Resources/mousectl"
codesign --force --sign - "$mouse_app"
