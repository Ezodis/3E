#!/bin/zsh
set -eu
cd "${0:A:h:h}"
exec zsh TouchBar/threee/Source/build.sh --touchtab-only
