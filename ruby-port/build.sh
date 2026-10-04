#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPINEL=${SPINEL:-$(command -v spinel || true)}

if [ ! -x "$SPINEL" ]; then
  echo "Spinel compiler not executable: $SPINEL" >&2
  echo "Set SPINEL to the installed spinel executable." >&2
  exit 1
fi

mkdir -p "$ROOT/build/bin"
(cd "$ROOT" && "$SPINEL" -I "$ROOT" bin/ttfx.rb -o build/bin/ttfx)

GUI_LINK=""
if [ -n "${TTFX_GUI_INCLUDE_DIR:-}" ]; then
  export CPATH="$TTFX_GUI_INCLUDE_DIR${CPATH:+:$CPATH}"
fi
if [ -n "${TTFX_GUI_LIBRARY_DIR:-}" ]; then
  GUI_LINK="--link -L$TTFX_GUI_LIBRARY_DIR"
fi
if [ "$(uname -s)" = Darwin ] && [ -d /opt/homebrew/include ]; then
  export CPATH="/opt/homebrew/include${CPATH:+:$CPATH}"
  GUI_LINK="$GUI_LINK --link -L/opt/homebrew/lib"
elif [ "$(uname -s)" = Darwin ] && [ -d /usr/local/include ]; then
  export CPATH="/usr/local/include${CPATH:+:$CPATH}"
  GUI_LINK="$GUI_LINK --link -L/usr/local/lib"
fi
# CPATH supplies custom header paths; Spinel --link supplies custom library
# search paths. Intentional word splitting expands repeated --link arguments.
# shellcheck disable=SC2086
(cd "$ROOT" && "$SPINEL" -I "$ROOT" ${GUI_LINK:-} bin/ttfx-gui.rb -o build/bin/ttfx-gui)

echo "Built $ROOT/build/bin/ttfx and ttfx-gui"
