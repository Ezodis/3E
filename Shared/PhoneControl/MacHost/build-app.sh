#!/bin/zsh
set -eu
phone_source="${0:A:h}"
phone_root="${phone_source:h:h:h}"
phone_app="$phone_root/build/phone/3E Phone.app"
mkdir -p "$phone_app/Contents/MacOS"
cat > "$phone_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.3e.phone</string><key>CFBundleName</key><string>3E Phone</string><key>CFBundleExecutable</key><string>3EPhone</string><key>CFBundleShortVersionString</key><string>1.0.17</string><key>CFBundleVersion</key><string>1.0.17</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSLocalNetworkUsageDescription</key><string>Connect your iPhone to this Mac as a trackpad and MIDI controller.</string></dict></plist>
PLIST
xcrun clang -arch arm64 -arch x86_64 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -framework AppKit -framework CoreImage -framework ApplicationServices "$phone_source/PhoneApp.m" -o "$phone_app/Contents/MacOS/3EPhone"
zsh "$phone_source/build-hosts.sh" "$phone_app"
codesign --force --sign - "$phone_app"
codesign --verify --deep --strict "$phone_app"
ditto -c -k --sequesterRsrc --keepParent "$phone_app" "$phone_root/build/phone/3E-Phone-Mac.zip"
printf 'Built %s\n' "$phone_app"
