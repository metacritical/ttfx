# Ruby port and raylib viewer

This directory contains a CRuby implementation of ttfx's legacy Rust engine
(`src/engine` and `src/effects`), plus a raylib window viewer. Spinel can compile
the Ruby programs into standalone terminal and GUI executables. The Rust
implementation remains authoritative.

The port registers all 37 effects and has deterministic parity fixtures for a
representative case of each effect. `verify.sh` compares a broader set of Ruby
and Spinel runs against the Rust legacy engine selected with `TTFX_FX=0`. This
is **legacy-engine compatibility**, not a port of the newer `src/fx` engine.
Option coverage and terminal input behavior are also narrower than the Rust
CLI; see the known limits below.

The raylib GUI is a viewer for one effect run. It starts fullscreen by default
(`--windowed` selects a window), and remains open showing the last frame until
Escape or the window close button. The Rust program is a terminal effect runner
that exits when the effect finishes; neither program implements an OS idle
screensaver or lock lifecycle.

## Build and run

Install Spinel and a C compiler. For the GUI, install raylib development
headers and library as well. Then run from this directory:

```sh
./build.sh
./build/bin/ttfx --list
printf 'hello' | ./build/bin/ttfx --seed 42 decrypt
./build/bin/ttfx-gui --windowed --text hello decrypt
```

Set `SPINEL` to the compiler path if it is not on `PATH`. The GUI accepts
`--font-size N`, `--font-path PATH`, `--frame-rate N` (or `--fps N`),
`--show-fps`, and `--windowed`. Its effect-option parsing is not yet as broad as
the Rust CLI. It does not recognize every Rust GUI spelling such as
`--showfps`; use `--show-fps` in this binary.

## Tests

Run the CRuby regression suite without Rust or Spinel:

```sh
./test.sh
```

It checks complete frame streams for all 37 registered effects against
Rust-derived SHA-256 fixtures, the synthgrid logo case, RNG, layout, scene
playback, easing, and the CLI effect list. The fixtures use fixed seeds,
canvas dimensions, and inputs recorded in
`test/fixtures/effect_goldens.json`. They cover one default case per effect,
not every option combination.

For broader cross-language checks, build the Rust release binary and Spinel
executables, then run:

```sh
cargo build --release
./build.sh
./verify.sh
```

`verify.sh` compares the CRuby and Spinel output against Rust over its listed
inputs and options. Ruby regression tests run in CI on macOS.

## Linux builds

The Rust CLI builds natively with stable Rust and Cargo using
`cargo build --release`; the repository CI also builds a static x86_64 musl
binary. The Rust CLI does not depend on raylib.

The Ruby terminal executable needs Spinel and a C compiler at build time. The
GUI also needs raylib headers and library at build time and raylib at runtime.
The build script detects standard Homebrew prefixes on macOS. On Linux, install
the distribution's raylib development package; standard include and library
paths are used. Set `TTFX_GUI_INCLUDE_DIR` for a custom header location and
`TTFX_GUI_LIBRARY_DIR` for a custom library location. The GUI is dynamically linked and is not a static musl artifact.

Spinel is a build-time tool and is not needed to run the compiled executables.
The Ruby source is currently shipped as part of this repository; it is not
packaged as a Ruby gem or stable library API.

## Known limits

- The frame engine and effect behavior follow Rust's legacy `src/effects`
  implementation. They do not implement the newer `src/fx` engine.
- Input handling supports plain text, not Rust's ANSI input parser or full
  terminal configuration and resize behavior.
- The terminal CLI supports a subset of Rust options. The raylib viewer has a
  smaller option surface and does not yet accept all Rust GUI option names.
- The GUI viewer holds the completed frame until its window closes; it does
  not exit automatically when the effect ends or provide OS screensaver
  integration.
- The GUI requires raylib at runtime; the terminal binary does not.
