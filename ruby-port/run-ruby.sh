#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec ruby -I "$ROOT" "$ROOT/bin/ttfx.rb" "$@"
