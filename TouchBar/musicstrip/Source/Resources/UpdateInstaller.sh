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
backup="$parent/.3E-previous-$$.app"
if [[ -e "$backup" ]]; then exit 1; fi
mv "$target" "$backup"
if mv "$candidate" "$target"; then
  /bin/rm -rf -- "$backup"
else
  mv "$backup" "$target"
  /usr/bin/open -a "$target"
  /bin/rm -rf -- "$work"
  /bin/rm -f -- "$installer"
  exit 1
fi
/bin/rm -rf -- "$work"
/bin/rm -f -- "$installer"
/usr/bin/open -a "$target"
