#!/bin/zsh
# One-time canonical name migration; never duplicate or overwrite an app.
set -eu
threee_old='/Applications/Strip3£.app'
threee_legacy='/Applications/3£.app'
threee_new='/Applications/3E.app'
if [[ ( -e "$threee_old" || -e "$threee_legacy" ) && -e "$threee_new" ]]; then
  printf 'Both an old and new app name exist. Resolve the duplicate before installing. No files changed.\n' >&2
  exit 1
fi
if [[ -e "$threee_old" || -e "$threee_legacy" ]]; then
  if pgrep -x ThreeE >/dev/null || pgrep -x 'MIDI Touchbar' >/dev/null; then
    printf 'Quit 3E before renaming. No files changed.\n' >&2; exit 1
  fi
  threee_source="$threee_legacy"
  [[ -e "$threee_old" ]] && threee_source="$threee_old"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$threee_source/Contents/Info.plist")" == local.musicstrip.app ]]
  /bin/mv "$threee_source" "$threee_new"
fi
