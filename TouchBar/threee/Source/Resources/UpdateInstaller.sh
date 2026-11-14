#!/bin/zsh
set -eu
candidate="$1"
target="$2"
work="$3"
main_pid="$4"
helper_pid="$5"
installer="$0"

# The app starts this detached helper before it quits. Wait until both the
# outer 3E process and its bundled MIDI engine have released the app bundle.
for attempt in {1..1800}; do
  main_alive=0
  helper_alive=0
  kill -0 "$main_pid" 2>/dev/null && main_alive=1 || true
  kill -0 "$helper_pid" 2>/dev/null && helper_alive=1 || true
  (( main_alive || helper_alive )) || break
  sleep 0.5
done
if kill -0 "$main_pid" 2>/dev/null || kill -0 "$helper_pid" 2>/dev/null; then
  /bin/rm -rf -- "$work"
  /bin/rm -f -- "$installer"
  exit 1
fi

parent="${target:h}"
# The app is named 3£. Older installs live at 3E.app or Strip3£.app; the
# update moves them to 3£.app (same bundle ID, settings and permissions).
destination="$target"
case "${target:t}" in
  3E.app|Strip3£.app) destination="$parent/3£.app" ;;
esac
if [[ "$destination" != "$target" && -e "$destination" ]]; then
  # Never overwrite something else that already uses the new name.
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null)" == local.musicstrip.app ]] || destination="$target"
fi
backup="$parent/.3E-previous-$$.app"
stale="$parent/.3E-replaced-$$.app"
if [[ -e "$backup" || -e "$stale" ]]; then exit 1; fi
mv "$target" "$backup"
# An old copy already at the new name is set aside, never mixed with the new one.
[[ "$destination" == "$target" || ! -e "$destination" ]] || mv "$destination" "$stale"
if mv "$candidate" "$destination"; then
  /bin/rm -rf -- "$backup" "$stale"
  # Forget the old path so Settings and Spotlight list only 3£.
  [[ "$destination" == "$target" ]] || /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$target" 2>/dev/null || true
else
  [[ ! -e "$stale" ]] || mv "$stale" "$destination"
  mv "$backup" "$target"
  /usr/bin/open -a "$target"
  /bin/rm -rf -- "$work"
  /bin/rm -f -- "$installer"
  exit 1
fi
/bin/rm -rf -- "$work"
/bin/rm -f -- "$installer"
/usr/bin/open -a "$destination"
