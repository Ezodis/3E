#!/bin/zsh
set -eu
cd "${0:A:h:h}"
xcodebuild -project TouchTab/Touch-Tab.xcodeproj -scheme Touch-Tab -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/TouchTab \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
touch_app="$PWD/build/TouchTab/Build/Products/Release/Touch-Tab.app"
codesign --force --sign "${TOUCHTAB_SIGNING_IDENTITY:--}" --timestamp=none \
  --entitlements TouchTab/Touch-Tab/Touch-Tab.entitlements "$touch_app"
codesign --verify --deep --strict "$touch_app"
printf 'Built %s. No automatic installation.\n' "$touch_app"
