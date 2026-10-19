#!/bin/zsh
# Install the exact verified combined build, avoiding mixed versions/modules.
set -eu
cd "${0:A:h:h}"
case "${1:-}" in
  "") zsh threee/Source/build.sh --combined ;;
  --built) ;;
  *) printf 'Usage: install-combined.sh [--built]\n' >&2; exit 2 ;;
esac
strip_source="$PWD/build/threee/3E.app"
strip_app='/Applications/3E.app'
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$strip_source/Contents/Info.plist")" == local.musicstrip.app ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print ThreeEIncludesTouchTab' "$strip_source/Contents/Info.plist")" == true ]]
codesign --verify --deep --strict "$strip_source"
"$strip_source/Contents/MacOS/ThreeE" --self-test
# Identify old and new executables by their bundle path, not branding.
if pgrep -f '/(3E|3£|Strip3£)\.app/Contents/' >/dev/null; then
  printf 'Quit 3E before installing. No installed files changed.\n' >&2; exit 1
fi
zsh threee/rename-installed.sh
if [[ -e "$strip_app" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$strip_app/Contents/Info.plist")" == local.musicstrip.app ]]
fi
strip_stage=$(mktemp -d /Applications/.threee-install.XXXXXX)
trap '[[ "$strip_stage" == /Applications/.threee-install.* ]] && /bin/rm -r -- "$strip_stage"' EXIT
ditto --norsrc --noextattr "$strip_source" "$strip_stage/3E.app"
codesign --verify --deep --strict "$strip_stage/3E.app"
[[ ! -e "$strip_app" ]] || /bin/mv "$strip_app" "$strip_stage/previous.app"
if ! /bin/mv "$strip_stage/3E.app" "$strip_app"; then
  [[ ! -e "$strip_stage/previous.app" ]] || /bin/mv "$strip_stage/previous.app" "$strip_app"
  exit 1
fi
printf 'Installed verified combined build at %s\n' "$strip_app"
