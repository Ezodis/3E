#!/bin/zsh
# One-time canonical name migration; never duplicate or overwrite an app.
set -eu
threee_old='/Applications/Strip3£.app'
threee_new='/Applications/3£.app'
if [[ -e "$threee_old" && -e "$threee_new" ]]; then
  printf 'Both old and new app names exist. Resolve the duplicate before installing. No files changed.\n' >&2
  exit 1
fi
if [[ -e "$threee_old" ]]; then
  if pgrep -x MusicStrip >/dev/null || pgrep -x 'MIDI Touchbar' >/dev/null; then
    printf 'Quit 3£ before renaming. No files changed.\n' >&2; exit 1
  fi
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$threee_old/Contents/Info.plist")" == local.musicstrip.app ]]
  /bin/mv "$threee_old" "$threee_new"
fi
