#!/bin/zsh
set -eu
cd "${0:A:h:h:h}"
dj_scratch=$(mktemp -d /tmp/threee-dj-test.XXXXXX)
trap '[[ "$dj_scratch" == /tmp/threee-dj-test.* ]] && /bin/rm -r -- "$dj_scratch"' EXIT
xcrun clang -fobjc-arc -O0 -Wno-unused-function -Wno-nonnull -framework AppKit -framework CoreMIDI threee/Tests/dj_surface.m -o "$dj_scratch/dj-test"
"$dj_scratch/dj-test"
