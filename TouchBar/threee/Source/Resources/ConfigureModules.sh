#!/bin/zsh
# Configure a staged app only; the running bundle is never edited in place.
set -eu
module_app="${1:?staged app}"
module_selection="${2?comma-separated modules}"
module_info="$module_app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$module_info")" == local.musicstrip.app ]]
module_ids=()
if [[ -n "$module_selection" ]]; then module_ids=("${(@s:,:)module_selection}"); fi
for module_id in "${module_ids[@]}"; do
  case "$module_id" in touchbar|touchtab|phone) ;; *) exit 2 ;; esac
done
# Validate every selected payload before removing anything.
for module_id in "${module_ids[@]}"; do
  case "$module_id" in
    touchbar) [[ -x "$module_app/Contents/Helpers/MIDI Touchbar.app/Contents/MacOS/MIDI Touchbar" && -x "$module_app/Contents/Helpers/ThreeE Apps.app/Contents/MacOS/ThreeEApps" ]] ;;
    touchtab) [[ -f "$module_app/Contents/Frameworks/ThreeEGestureEngine.dylib" ]] ;;
    phone) for module_arch in arm64 x64; do [[ -x "$module_app/Contents/Resources/PhoneControl/$module_arch/ThreeE.PhoneHost" ]]; done ;;
  esac
done
if (( ! ${module_ids[(Ie)touchbar]} )); then
  rm -rf -- "$module_app/Contents/Helpers/MIDI Touchbar.app" "$module_app/Contents/Helpers/ThreeE Apps.app" "$module_app/Contents/Resources/Ableton"
fi
if (( ! ${module_ids[(Ie)touchtab]} )); then
  rm -f -- "$module_app/Contents/Frameworks/ThreeEGestureEngine.dylib"
fi
if (( ! ${module_ids[(Ie)phone]} )); then
  rm -rf -- "$module_app/Contents/Resources/PhoneControl"
fi
/usr/libexec/PlistBuddy -c 'Delete ThreeEModules' "$module_info" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add ThreeEModules array' "$module_info"
for module_id in "${module_ids[@]}"; do
  /usr/libexec/PlistBuddy -c "Add ThreeEModules: string $module_id" "$module_info"
done
plutil -replace ThreeEModuleSchema -integer 1 "$module_info"
plutil -replace LSMinimumSystemVersion -string 12.0 "$module_info"
if (( ${module_ids[(Ie)touchtab]} )); then
  plutil -replace ThreeEIncludesTouchTab -bool YES "$module_info"
else
  plutil -replace ThreeEIncludesTouchTab -bool NO "$module_info"
fi
# Keep the local development identity when available, but never require that
# private key on another user's Mac. CI and public installs use ad-hoc signing.
module_identity="${STRIP_SIGNING_IDENTITY:-}"
if [[ -z "$module_identity" ]]; then
  module_identity=-
  if security find-identity -v -p codesigning | /usr/bin/grep -q EDA0E1C9F0DD46BE3437CD2733933E31D3A8623D; then
    module_identity=EDA0E1C9F0DD46BE3437CD2733933E31D3A8623D
  fi
fi
codesign --force --sign "$module_identity" --timestamp=none "$module_app"
codesign --verify --deep --strict "$module_app"
