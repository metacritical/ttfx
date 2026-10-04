# Effects module: static registry (mirrors ttfx src/effects/mod.rs).
# decrypt is faithful (scene machine); the rest are simplified effects on
# the legacy repaint loop.
require "ttfx/effects/wipe"
require "ttfx/effects/decrypt"
require "ttfx/effects/beams"
require "ttfx/effects/waves"
require "ttfx/effects/matrix"
require "ttfx/effects/rain"
require "ttfx/effects/highlight"
require "ttfx/effects/randomsequence"
require "ttfx/effects/scattered"
require "ttfx/effects/expand"
require "ttfx/effects/spray"
require "ttfx/effects/bouncyballs"
require "ttfx/effects/sweep"
require "ttfx/effects/middleout"
require "ttfx/effects/smoke"
require "ttfx/effects/slice"
require "ttfx/effects/overflow"
require "ttfx/effects/pour"
require "ttfx/effects/slide"
require "ttfx/effects/spotlights"
require "ttfx/effects/burn"
require "ttfx/effects/orbittingvolley"
require "ttfx/effects/print"
require "ttfx/effects/fireworks"
require "ttfx/effects/colorshift"
require "ttfx/effects/binarypath"
require "ttfx/effects/errorcorrect"
require "ttfx/effects/rings"
require "ttfx/effects/remaining"

module Effects
  # name -> [kind, class, description]
  REGISTRY = {
    "wipe" => ["faithful", WipeEffect, "Wipes the text across the terminal to reveal characters"],
    "decrypt" => ["faithful", DecryptEffect, "Display a movie style decryption effect"],
    "beams" => ["faithful", BeamsEffect, "Create beams which travel over the canvas illuminating the characters behind them"],
    "waves" => ["faithful", WavesEffect, "Waves travel across the terminal leaving behind the characters"],
    "matrix" => ["faithful", MatrixEffect, "Matrix digital rain effect"],
    "rain" => ["faithful", RainEffect, "Rain characters from the top of the canvas"],
    "highlight" => ["faithful", HighlightEffect, "Run a specular highlight across the text"],
    "randomsequence" => ["faithful", RandomsequenceEffect, "Prints the input data in a random sequence"],
    "scattered" => ["faithful", ScatteredEffect, "Text is scattered across the canvas and moves into position"],
    "expand" => ["faithful", ExpandEffect, "Expands the text from a single point"],
    "spray" => ["faithful", SprayEffect, "Draws the characters spawning at varying rates from a single point"],
    "bouncyballs" => ["faithful", BouncyballsEffect, "Characters are bouncy balls falling from the top of the canvas"],
    "middleout" => ["faithful", MiddleoutEffect, "Text expands in a single row or column in the middle of the canvas then out"],
    "smoke" => ["faithful", SmokeEffect, "Smoke floods the canvas colorizing any characters it crosses"],
    "slice" => ["faithful", SliceEffect, "Slices the input in half and slides it into place from opposite directions"],
    "overflow" => ["faithful", OverflowEffect, "Input text overflows and scrolls the terminal in a random order until eventually appearing ordered"],
    "pour" => ["faithful", PourEffect, "Pours the characters into position from the given direction"],
    "slide" => ["faithful", SlideEffect, "Slide characters into view from outside the terminal"],
    "spotlights" => ["faithful", SpotlightsEffect, "Spotlights search the text area, illuminating characters, before converging in the center and expanding"],
    "burn" => ["faithful", BurnEffect, "Burns vertically in the canvas"],
    "print" => ["faithful", PrintEffect, "Lines are printed one at a time following a print head. Print head performs line feed, carriage return"],
    "fireworks" => ["faithful", FireworksEffect, "Characters launch and explode like fireworks and fall into place"],
    "orbittingvolley" => ["faithful", OrbittingvolleyEffect, "Four launchers orbit the canvas firing volleys of characters inward to build the input text from the center out"],
    "colorshift" => ["faithful", ColorshiftEffect, "Display a gradient that shifts colors across the terminal"],
    "binarypath" => ["faithful", BinarypathEffect, "Binary characters travel a path and form into the input text"],
    "errorcorrect" => ["faithful", ErrorcorrectEffect, "Some characters start in the wrong position and are corrected"],
    "rings" => ["faithful", RingsEffect, "Characters are dispersed and form into spinning rings"],
    "sweep" => ["faithful", SweepEffect, "Sweep across the canvas to reveal uncolored text, reverse sweep to color the text"],
    "swarm" => ["faithful", SwarmEffect, "Character swarms move through focus areas and settle into position"],
    "crumble" => ["faithful", CrumbleEffect, "Characters crumble to dust, are vacuumed, and reform"],
    "unstable" => ["faithful", UnstableEffect, "Jumbled characters rumble, explode outward, and reassemble"],
    "laseretch" => ["faithful", LaseretchEffect, "A laser etches characters onto the terminal"],
    "bubbles" => ["faithful", BubblesEffect, "Characters float down as bubbles, pop, and return to position"],
    "synthgrid" => ["faithful", SynthgridEffect, "A grid expands as characters dissolve into place"],
    "blackhole" => ["faithful", BlackholeEffect, "Characters are consumed by a black hole and burst outward"],
    "vhstape" => ["faithful", VhstapeEffect, "VHS scanline glitches distort and restore the text"],
    "thunderstorm" => ["faithful", ThunderstormEffect, "A storm of rain and lightning flashes across the text"],
  }

  def self.names
    REGISTRY.keys
  end

  def self.kind(name)
    entry = REGISTRY[name]
    return nil if entry.nil?
    entry[0]
  end

  def self.build_legacy(name, engine)
    entry = REGISTRY[name]
    return nil if entry.nil? || entry[0] != "legacy"
    entry[1].new(engine)
  end
end
