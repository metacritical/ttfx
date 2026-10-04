# ttfx-rb: terminal text effects in Spinel-compilable Ruby.
#
# decrypt and wipe are faithful ports of ttfx (old-engine semantics,
# byte-identical frames given the same seed); beams/waves/matrix/rain are
# architecture-faithful simplifications sharing the layout + RNG core.

require "ttfx/rng"
require "ttfx/easing"
require "ttfx/color"
require "ttfx/terminal"
require "ttfx/canvas"
require "ttfx/scene"
require "ttfx/spanning"
require "ttfx/particles"
require "ttfx/engine"
require "ttfx/effects"
