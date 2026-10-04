#!/bin/sh
# Run the not-yet-ported effects one at a time in the GUI.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUI="$HERE/../build/bin/ttfx-gui"
INPUT=${1:-"$HERE/../logo.txt"}

if [ ! -x "$GUI" ]; then
  echo "Missing $GUI; run ./build.sh first" >&2
  exit 1
fi
if [ ! -f "$INPUT" ]; then
  echo "Input file not found: $INPUT" >&2
  exit 1
fi

for effect in swarm crumble unstable laseretch bubbles synthgrid blackhole vhstape thunderstorm; do
  printf '\nStarting %s (close the window or press Escape for the next effect)\n' "$effect"
  "$GUI" --windowed -i "$INPUT" "$effect" --show-fps
done
