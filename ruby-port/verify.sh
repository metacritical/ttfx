#!/bin/sh
# Full parity verification for the ruby-port faithful effects.
# Compares CRuby oracle vs Rust (old engine via TTFX_FX=0), then the Spinel
# binary vs CRuby, plus CLI exit codes and determinism. Needs no tty:
# everything runs piped (both sides fall back to 80x24).
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REF="$ROOT/../target/release/ttfx"
RUBY="ruby -I$ROOT $ROOT/bin/ttfx.rb"
SPIN="$ROOT/build/bin/ttfx"
PASS=0
FAIL=0

need() {
  if [ ! -x "$1" ]; then echo "missing executable: $1" >&2; exit 2; fi
}
need "$REF"
if [ ! -x "$SPIN" ]; then echo "missing $SPIN (run ./build.sh first)" >&2; exit 2; fi

# cmp_case <desc> <text> <pre-effect args> <effect> [post-effect args...]
# Pre-effect args go before the effect name for Rust (clap requires terminal
# options first); ours is order-free so the same strings work anywhere.
cmp_case() {
  desc=$1; text=$2; pre=$3; effect=$4; shift 4
  # shellcheck disable=SC2086
  printf '%s' "$text" | TTFX_FX=0 $REF --seed 42 $pre --parity-dump $effect $* \
    > /tmp/v_rust.txt 2>/tmp/v_rust.err
  # shellcheck disable=SC2086
  $RUBY --seed 42 --dump-frames --text "$text" $pre $effect $* \
    > /tmp/v_ruby.txt 2>/tmp/v_ruby.err
  if [ "$(cat /tmp/v_rust.err)" = "$(cat /tmp/v_ruby.err)" ] && \
     cmp -s /tmp/v_rust.txt /tmp/v_ruby.txt; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); echo "FAIL(rust) $desc"
  fi
  # shellcheck disable=SC2086
  $SPIN --seed 42 --dump-frames --text "$text" $pre $effect $* \
    > /tmp/v_spin.txt 2>/dev/null
  if cmp -s /tmp/v_ruby.txt /tmp/v_spin.txt; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); echo "FAIL(spin) $desc"
  fi
}

# expect_exit <code> <desc> <args...> (empty piped stdin)
expect_exit() {
  code=$1; desc=$2; shift 2
  # shellcheck disable=SC2086
  printf '' | $RUBY $* >/dev/null 2>&1
  # shellcheck disable=SC2086
  got=0; printf '' | $RUBY $* >/dev/null 2>&1 || got=$?
  if [ "$got" = "$code" ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); echo "FAIL(exit $got!=$code) $desc"; fi
}

echo "== decrypt =="
cmp_case "decrypt basic" "hi" "" decrypt
cmp_case "decrypt words" "hello world" "" decrypt
cmp_case "decrypt logo" "$(cat "$ROOT/logo.txt")" "" decrypt
cmp_case "decrypt opts" "opts" "" decrypt --typing-speed 3 \
  --ciphertext-colors ff0000 00ff00 \
  --final-gradient-stops 0000ff ffff00 --final-gradient-steps 5 8 \
  --final-gradient-direction horizontal
cmp_case "decrypt diagonal" "diag" "" decrypt --final-gradient-direction diagonal
cmp_case "decrypt tabs" "a	b" "--tab-width 8" decrypt
for a in n ne e se s sw w nw c; do
  cmp_case "decrypt anchor-text $a" "hi there" "--anchor-text $a" decrypt
done
for a in n c ne; do
  cmp_case "decrypt anchor-canvas $a" "hi there" "--anchor-canvas $a" decrypt
done

echo "== wipe =="
cmp_case "wipe basic" "hi" "" wipe
cmp_case "wipe words" "hello world" "" wipe
cmp_case "wipe logo" "$(cat "$ROOT/logo.txt")" "" wipe
for g in column_left_to_right column_right_to_left row_top_to_bottom \
  row_bottom_to_top diagonal_bottom_left_to_top_right \
  diagonal_top_right_to_bottom_left diagonal_top_left_to_bottom_right \
  diagonal_bottom_right_to_top_left center_to_outside outside_to_center; do
  cmp_case "wipe group $g" "wipe me" "" wipe --wipe-direction "$g"
done
for e in linear in_sine out_sine in_out_sine in_quad out_quad in_out_quad \
  in_cubic out_cubic in_out_cubic in_quart out_quart in_out_quart in_quint \
  out_quint in_out_quint in_expo out_expo in_out_expo in_circ out_circ \
  in_out_circ in_back out_back in_out_back in_elastic out_elastic \
  in_out_elastic in_bounce out_bounce in_out_bounce; do
  cmp_case "wipe ease $e" "easing test" "" wipe --wipe-ease "$e"
done
cmp_case "wipe delay" "delayed" "" wipe --wipe-delay 2
cmp_case "wipe frames" "framed" "" wipe --final-gradient-frames 1 \
  --final-gradient-steps 5
cmp_case "wipe anchors" "anchored text here" "--anchor-text c --anchor-canvas ne" \
  wipe --wipe-direction center_to_outside

echo "== rain =="
cmp_case "rain basic" "hi" "" rain
cmp_case "rain words" "hello world" "" rain
cmp_case "rain logo" "$(cat "$ROOT/logo.txt")" "" rain
cmp_case "rain speed" "ABC def" "" rain --movement-speed 0.5-0.9
cmp_case "rain opts" "opts" "" rain --rain-colors ff0000 00ff00 \
  --rain-symbols x + --movement-easing out_quad \
  --final-gradient-direction horizontal
cmp_case "rain multiline" "multi
line here" "" rain

echo "== waves =="
cmp_case "waves basic" "hi" "" waves
cmp_case "waves words" "hello world" "" waves
cmp_case "waves logo" "$(cat "$ROOT/logo.txt")" "" waves
cmp_case "waves row" "ABC" "" waves --wave-direction row_top_to_bottom
cmp_case "waves center" "dir test" "" waves --wave-direction center_to_outside
cmp_case "waves ease" "ease me" "" waves --wave-easing out_bounce --wave-count 3
cmp_case "waves opts" "opts" "" waves --wave-count 2 --wave-length 3 --wave-gradient-steps 4
cmp_case "waves syms" "sym" "" waves --wave-symbols a b c

echo "== beams =="
cmp_case "beams basic" "hi" "" beams
cmp_case "beams words" "hello world" "" beams
cmp_case "beams logo" "$(cat "$ROOT/logo.txt")" "" beams
cmp_case "beams delay" "ABC def" "" beams --beam-delay 2
cmp_case "beams opts" "opts" "" beams --beam-row-symbols x y --beam-column-symbols + --beam-row-speed-range 5-10
cmp_case "beams wipe" "The quick brown fox" "" beams --final-wipe-speed 1 --beam-gradient-frames 1
cmp_case "beams multiline" "multi
line" "" beams --final-gradient-direction horizontal

echo "== matrix =="
cmp_case "matrix basic" "hi" "" matrix --rain-time 2
cmp_case "matrix words" "hello world" "" matrix --rain-time 2
cmp_case "matrix logo" "$(cat "$ROOT/logo.txt")" "" matrix --rain-time 2
cmp_case "matrix resolve" "ABC" "" matrix --rain-time 1 --resolve-delay 1
cmp_case "matrix opts" "opts" "" matrix --rain-time 2 --rain-fall-delay-range 1-3 \
  --rain-column-delay-range 1-2 --symbol-swap-chance 0.05 --color-swap-chance 0.02
cmp_case "matrix gradient" "grad" "" matrix --rain-time 2 --final-gradient-direction vertical
cmp_case "matrix full" "matrix full" "" matrix

echo "== highlight =="
cmp_case "highlight basic" "hi" "" highlight
cmp_case "highlight words" "hello world" "" highlight
cmp_case "highlight logo" "$(cat "$ROOT/logo.txt")" "" highlight
cmp_case "highlight dir" "ABC" "" highlight --highlight-direction row_top_to_bottom --highlight-width 3
cmp_case "highlight bright" "bright" "" highlight --highlight-brightness 2.5

echo "== randomsequence =="
cmp_case "randomsequence basic" "hi" "" randomsequence
cmp_case "randomsequence words" "hello world" "" randomsequence
cmp_case "randomsequence logo" "$(cat "$ROOT/logo.txt")" "" randomsequence
cmp_case "randomsequence speed" "speedy Gonzales" "" randomsequence --speed 0.05
cmp_case "randomsequence frames" "framed" "" randomsequence --final-gradient-frames 2

echo "== scattered =="
cmp_case "scattered basic" "hi" "" scattered
cmp_case "scattered words" "hello world" "" scattered
cmp_case "scattered logo" "$(cat "$ROOT/logo.txt")" "" scattered
cmp_case "scattered speed" "ABC" "" scattered --movement-speed 1.5
cmp_case "scattered ease" "ease test" "" scattered --movement-easing out_bounce
cmp_case "scattered frames" "framed" "" scattered --final-gradient-frames 3 --final-gradient-direction horizontal

echo "== expand =="
cmp_case "expand basic" "hi" "" expand
cmp_case "expand words" "hello world" "" expand
cmp_case "expand logo" "$(cat "$ROOT/logo.txt")" "" expand
cmp_case "expand ease" "ABC" "" expand --expand-easing out_bounce --movement-speed 0.8
cmp_case "expand gradient" "grad" "" expand --final-gradient-direction diagonal

echo "== middleout =="
cmp_case "middleout basic" "hi" "" middleout
cmp_case "middleout words" "middle out test" "" middleout
cmp_case "middleout logo" "$(cat "$ROOT/logo.txt")" "" middleout
cmp_case "middleout dir" "dir" "" middleout --expand-direction horizontal
cmp_case "middleout speed" "spd" "" middleout --center-movement-speed 1.2 --full-movement-speed 0.9 --center-easing linear
cmp_case "middleout multi" "a
bb
ccc" "" middleout

echo "== slice =="
cmp_case "slice basic" "hi" "" slice
cmp_case "slice words" "slice it" "" slice
cmp_case "slice logo" "$(cat "$ROOT/logo.txt")" "" slice
cmp_case "slice horiz" "dir" "" slice --slice-direction horizontal
cmp_case "slice diag" "dia" "" slice --slice-direction diagonal
cmp_case "slice speed" "spd" "" slice --movement-speed 0.8 --movement-easing linear
cmp_case "slice multi" "a
bb
ccc" "" slice --slice-direction horizontal

echo "== overflow =="
cmp_case "overflow basic" "hi" "" overflow
cmp_case "overflow words" "overflowing text" "" overflow
cmp_case "overflow logo" "$(cat "$ROOT/logo.txt")" "" overflow
cmp_case "overflow cycles" "cyc" "" overflow --overflow-cycles-range 1-1 --overflow-speed 1
cmp_case "overflow multi" "multi
line test" "" overflow

echo "== pour =="
cmp_case "pour basic" "hi" "" pour
cmp_case "pour words" "pour it" "" pour
cmp_case "pour logo" "$(cat "$ROOT/logo.txt")" "" pour
cmp_case "pour up" "up" "" pour --pour-direction up
cmp_case "pour left" "left" "" pour --pour-direction left
cmp_case "pour right" "right" "" pour --pour-direction right
cmp_case "pour opts" "opts" "" pour --pour-speed 1 --gap 0 --movement-speed-range 1.0-2.0

echo "== print =="
cmp_case "print basic" "hi" "" print
cmp_case "print words" "printing lines" "" print
cmp_case "print logo" "$(cat "$ROOT/logo.txt")" "" print
cmp_case "print speed" "spd" "" print --print-speed 1 --print-head-easing linear
cmp_case "print multi" "a
bb
ccc" "" print

echo "== orbittingvolley =="
cmp_case "orbittingvolley basic" "hi" "" orbittingvolley
cmp_case "orbittingvolley words" "volley fire" "" orbittingvolley
cmp_case "orbittingvolley logo" "$(cat "$ROOT/logo.txt")" "" orbittingvolley
cmp_case "orbittingvolley syms" "sym" "" orbittingvolley --top-launcher-symbol X --character-easing linear
cmp_case "orbittingvolley multi" "multi
line test" "" orbittingvolley

echo "== fireworks =="
cmp_case "fireworks basic" "hi" "" fireworks
cmp_case "fireworks words" "boom box" "" fireworks
cmp_case "fireworks logo" "$(cat "$ROOT/logo.txt")" "" fireworks
cmp_case "fireworks anywhere" "any" "" fireworks --explode-anywhere --launch-delay 2
cmp_case "fireworks opts" "opts" "" fireworks --firework-volume 0.2 --explode-distance 0.5
cmp_case "fireworks multi" "a
bb
ccc" "" fireworks

echo "== binarypath =="
cmp_case "binarypath basic" "hi" "" binarypath
cmp_case "binarypath words" "binary ride" "" binarypath
cmp_case "binarypath logo" "$(cat "$ROOT/logo.txt")" "" binarypath
cmp_case "binarypath opts" "spd" "" binarypath --movement-speed 2.0 --active-binary-groups 0.5
cmp_case "binarypath multi" "a
bb
ccc" "" binarypath

echo "== errorcorrect =="
cmp_case "errorcorrect empty" "hi there" "" errorcorrect
cmp_case "errorcorrect words" "error correction test" "" errorcorrect
cmp_case "errorcorrect logo" "$(cat "$ROOT/logo.txt")" "" errorcorrect
cmp_case "errorcorrect opts" "lots of errors here yes" "" errorcorrect --error-pairs 0.3 --swap-delay 2

echo "== remaining effects (smoke and backend parity) =="
for effect in swarm crumble unstable laseretch bubbles synthgrid blackhole vhstape thunderstorm; do
  cmp_case "$effect basic" "hi" "" "$effect"
done

echo "== burn =="
cmp_case "burn basic" "hi" "" burn
cmp_case "burn words" "burn baby" "" burn
cmp_case "burn logo" "$(cat "$ROOT/logo.txt")" "" burn
cmp_case "burn nosmoke" "nosmoke" "" burn --smoke-chance 0
cmp_case "burn opts" "opts" "" burn --starting-color ff0000 --burn-colors 00ff00 ffff00

echo "== slide =="
cmp_case "slide basic" "hi" "" slide
cmp_case "slide words" "sliding in" "" slide
cmp_case "slide logo" "$(cat "$ROOT/logo.txt")" "" slide
cmp_case "slide column" "col" "" slide --grouping column
cmp_case "slide diagonal" "dia" "" slide --grouping diagonal
cmp_case "slide merge" "mrg" "" slide --merge
cmp_case "slide reverse" "rev" "" slide --reverse-direction
cmp_case "slide gap" "gap" "" slide --gap 0 --movement-easing linear

echo "== spotlights =="
cmp_case "spotlights basic" "hi" "" spotlights --search-duration 5
cmp_case "spotlights words" "spot on" "" spotlights --search-duration 8
cmp_case "spotlights logo" "$(cat "$ROOT/logo.txt")" "" spotlights --search-duration 5
cmp_case "spotlights count" "cnt" "" spotlights --search-duration 5 --spotlight-count 1
cmp_case "spotlights falloff" "fall" "" spotlights --search-duration 5 --beam-falloff 0.0 --beam-width-ratio 1.0

echo "== colorshift =="
cmp_case "colorshift basic" "hi" "" colorshift
cmp_case "colorshift words" "shifting colors" "" colorshift
cmp_case "colorshift logo" "$(cat "$ROOT/logo.txt")" "" colorshift
cmp_case "colorshift cycles" "cyc" "" colorshift --cycles 1
cmp_case "colorshift skip" "skip" "" colorshift --skip-final-gradient
cmp_case "colorshift noloop" "noloop" "" colorshift --no-loop
cmp_case "colorshift notravel" "notrav" "" colorshift --no-travel
cmp_case "colorshift reverse" "rev" "" colorshift --reverse-travel-direction
cmp_case "colorshift horiz" "horiz" "" colorshift --travel-direction horizontal

echo "== smoke =="
cmp_case "smoke basic" "hi" "" smoke
cmp_case "smoke words" "smoke test" "" smoke
cmp_case "smoke logo" "$(cat "$ROOT/logo.txt")" "" smoke
cmp_case "smoke syms" "sym" "" smoke --smoke-symbols x +
cmp_case "smoke whole" "whole" "" smoke --use-whole-canvas
cmp_case "smoke multi" "multi
line here" "" smoke

echo "== spray =="
cmp_case "spray basic" "hi" "" spray
cmp_case "spray words" "hello world" "" spray
cmp_case "spray logo" "$(cat "$ROOT/logo.txt")" "" spray
for pos in n ne e se s sw w nw center; do
  cmp_case "spray pos $pos" "pos" "" spray --spray-position "$pos"
done
cmp_case "spray opts" "opts" "" spray --spray-volume 0.05 --movement-speed-range 1.0-2.0 --movement-easing in_quad
cmp_case "spray multiline" "multi
line" "" spray

echo "== bouncyballs =="
cmp_case "bouncyballs basic" "hi" "" bouncyballs
cmp_case "bouncyballs words" "bouncing balls fall" "" bouncyballs
cmp_case "bouncyballs logo" "$(cat "$ROOT/logo.txt")" "" bouncyballs
cmp_case "bouncyballs opts" "ABC" "" bouncyballs --ball-delay 1 --movement-speed 0.9
cmp_case "bouncyballs symbols" "opts" "" bouncyballs --ball-colors ff0000 --ball-symbols X --movement-easing linear
cmp_case "bouncyballs multi" "line one
line two
line three" "" bouncyballs

echo "== sweep =="
cmp_case "sweep basic" "hi" "" sweep
cmp_case "sweep words" "sweep it" "" sweep
cmp_case "sweep logo" "$(cat "$ROOT/logo.txt")" "" sweep
cmp_case "sweep dirs" "dir" "" sweep --first-sweep-direction row_top_to_bottom --second-sweep-direction column_left_to_right
cmp_case "sweep syms" "sym" "" sweep --sweep-symbols x +

echo "== CLI =="
expect_exit 1 "no input" decrypt
expect_exit 1 "usage"
expect_exit 0 "list" --list
expect_exit 1 "bad anchor" --anchor-text xx decrypt --text hi
expect_exit 1 "bad ease" wipe --wipe-ease nope --text hi
expect_exit 1 "bad direction" decrypt --final-gradient-direction up --text hi
expect_exit 1 "empty filter" --random-effect \
  --exclude-effects wipe decrypt beams waves matrix rain highlight randomsequence scattered expand spray bouncyballs sweep middleout smoke slice colorshift overflow pour slide spotlights burn orbittingvolley print fireworks binarypath errorcorrect rings swarm crumble unstable laseretch bubbles synthgrid blackhole vhstape thunderstorm --text hi
d1=$(printf hi | $RUBY --seed 77 --random-effect --dump-frames --text hi 2>/dev/null | md5)
d2=$(printf hi | $RUBY --seed 77 --random-effect --dump-frames --text hi 2>/dev/null | md5)
if [ "$d1" = "$d2" ]; then PASS=$((PASS + 1)); else
  FAIL=$((FAIL + 1)); echo "FAIL(determinism) random-effect"; fi

echo "== units (CRuby vs Spinel agree; values pinned) =="
u1=$(ruby -I"$ROOT" -rttfx/rng -e '
r = Rng.new(42)
w = r.next_word
puts((w[0] + (w[1] << 16) + (w[2] << 32) + (w[3] << 48)).to_s(16))' 2>/dev/null)
if [ "$u1" = "d0764d4f4476689f" ]; then PASS=$((PASS + 1)); else
  FAIL=$((FAIL + 1)); echo "FAIL(unit) rng seed42 got $u1"; fi
u2=$(ruby -I"$ROOT" -rttfx/color -e '
g = Gradient.with_steps([[255, 255, 255], [237, 160, 0]], 10, false)
puts g.spectrum[1].inspect' 2>/dev/null)
if [ "$u2" = "[253, 245, 229]" ]; then PASS=$((PASS + 1)); else
  FAIL=$((FAIL + 1)); echo "FAIL(unit) gradient got $u2"; fi

echo "pass=$PASS fail=$FAIL"
exit "$([ "$FAIL" = 0 ] && echo 0 || echo 1)"
