#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/RecordCompanion.app/Contents/MacOS
cp Info.plist build/RecordCompanion.app/Contents/Info.plist
xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 -mmacosx-version-min=11.0 \
  -framework AppKit -framework ApplicationServices main.m -o build/RecordCompanion.app/Contents/MacOS/RecordCompanion
codesign --force --sign - build/RecordCompanion.app
codesign --verify --deep --strict build/RecordCompanion.app
echo "Built record-companion/build/RecordCompanion.app"
