#!/bin/zsh
set -eu
phone_source="${0:A:h}"
phone_root="${phone_source:h:h:h}"
STRIP_SIGNING_IDENTITY="${STRIP_SIGNING_IDENTITY:--}" zsh "$phone_root/TouchBar/threee/Source/build.sh" --phone-only
mkdir -p "$phone_root/build/phone"
ditto -c -k --sequesterRsrc --keepParent "$phone_root/TouchBar/build/threee/3E.app" "$phone_root/build/phone/3E-Phone-Mac.zip"
