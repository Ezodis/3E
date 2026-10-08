#!/bin/zsh
set -eu
cd "${0:A:h}"
root="${PWD:h:h}"
ditto --norsrc --noextattr "$root/recovered/Strip3£.app" "$root/legacy-build/Strip3£.app"
xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -O2 \
  -mmacosx-version-min=11.0 -framework AppKit -framework Carbon -framework ApplicationServices \
  main.m -o "$root/legacy-build/Strip3£.app/Contents/MacOS/MusicStrip"
codesign --force --sign - "$root/legacy-build/Strip3£.app/Contents/MacOS/MusicStrip"
codesign --verify --strict "$root/legacy-build/Strip3£.app/Contents/MacOS/MusicStrip"
echo "Built legacy-build/Strip3£.app; the recovered MIDI helper remains unchanged."
