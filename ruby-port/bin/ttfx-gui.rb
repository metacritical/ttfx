# ttfx-gui entry point: faithful + legacy effects drawn in a raylib window.
# Usage: ttfx-gui <effect> [--text "..."] [--seed N]
require "ttfx"
require "ttfx/gui"

def read_input
  idx = ARGV.index("--text")
  unless idx.nil?
    v = ARGV[idx + 1]
    return v unless v.nil?
  end
  idx = ARGV.index("--input-file")
  idx = ARGV.index("-i") if idx.nil?
  unless idx.nil?
    path = ARGV[idx + 1]
    unless path.nil?
      begin
        return File.read(path)
      rescue StandardError
        return ""
      end
    end
  end
  return "" if $stdin.tty?
  begin
    $stdin.read
  rescue StandardError
    ""
  end
end

def flag_value(name)
  idx = ARGV.index(name)
  return nil if idx.nil?
  ARGV[idx + 1]
end

# Multi-value option: --opt a b c (values until next flag or effect name).
def flag_values(name)
  idx = ARGV.index(name)
  return nil if idx.nil?
  vals = []
  i = idx + 1
  while i < ARGV.length
    a = ARGV[i]
    break if a[0, 2] == "--"
    vals.push(a)
    i += 1
  end
  vals
end

def main
  if ARGV.include?("--list") || ARGV.include?("-l")
    Effects.names.each do |n|
      puts("#{n}: #{Effects::REGISTRY[n][2]}")
    end
    return 0
  end

  name = ARGV.find { |a| Effects::REGISTRY.key?(a) }
  seed_text = flag_value("--seed")
  seed = seed_text.nil? ? 12345 : seed_text.to_i
  rng = Rng.new(seed)
  # --random-effect wins over an explicit effect; the selection draw comes
  # out of the same stream the engine then uses.
  if ARGV.include?("--random-effect") || ARGV.include?("-R")
    names = Effects.names
    inc = flag_values("--include-effects")
    names = names.select { |n| inc.include?(n) } unless inc.nil? || inc.empty?
    exc = flag_values("--exclude-effects")
    names = names.reject { |n| exc.include?(n) } unless exc.nil? || exc.empty?
    if names.empty?
      STDERR.puts("Error: No effects available after filtering.")
      return 1
    end
    name = names[rng.choice_index(names.length)]
  end
  if name.nil?
    puts("usage: ttfx-gui [options] <effect> | --list")
    puts("effects: #{Effects.names.join(', ')}")
    return 1
  end

  text = read_input
  text = "NO INPUT." if text.strip.empty?

  seed_text = flag_value("--seed")
  seed = seed_text.nil? ? 12345 : seed_text.to_i

  # Window-sized canvas (input-sized up to 256x256 so large logos are
  # never clipped); the window fits the canvas at --font-size glyphs.
  canvas = Canvas.new(256, 256, text)
  font_text = flag_value("--font-size")
  font_size = font_text.nil? ? 36 : font_text.to_i
  windowed = ARGV.include?("--windowed")
  font_path = flag_value("--font-path")
  fr = flag_value("--frame-rate")
  fr = flag_value("--fps") if fr.nil?
  fps = 60
  unless fr.nil?
    ok = fr =~ /\A-?\d+\z/ && fr.to_i >= 0
    unless ok
      if fr =~ /\A-?\d+\z/
        puts("#{fr.to_i} is not >= 0")
      else
        puts("invalid int value: '#{fr}'")
      end
      return 1
    end
    fps = fr.to_i
  end
  gui = GuiEngine.new(canvas, rng, font_size, !windowed, font_path, fps, ARGV.include?("--show-fps"))
  if Effects.kind(name) == "faithful"
    ctx = EngineCtx.new(canvas, rng)
    ctx.frame_rate = fps
    if name == "decrypt"
      effect = DecryptEffect.new(ctx, {})
    elsif name == "waves"
      effect = WavesEffect.new(ctx, {})
    elsif name == "rain"
      effect = RainEffect.new(ctx, {})
    elsif name == "beams"
      effect = BeamsEffect.new(ctx, {})
    elsif name == "matrix"
      effect = MatrixEffect.new(ctx, {})
    elsif name == "highlight"
      effect = HighlightEffect.new(ctx, {})
    elsif name == "randomsequence"
      effect = RandomsequenceEffect.new(ctx, {})
    elsif name == "scattered"
      effect = ScatteredEffect.new(ctx, {})
    elsif name == "expand"
      effect = ExpandEffect.new(ctx, {})
    elsif name == "spray"
      effect = SprayEffect.new(ctx, {})
    elsif name == "bouncyballs"
      effect = BouncyballsEffect.new(ctx, {})
    elsif name == "sweep"
      effect = SweepEffect.new(ctx, {})
    elsif name == "middleout"
      effect = MiddleoutEffect.new(ctx, {})
    elsif name == "smoke"
      effect = SmokeEffect.new(ctx, {})
    elsif name == "slice"
      effect = SliceEffect.new(ctx, {})
    elsif name == "overflow"
      effect = OverflowEffect.new(ctx, {})
    elsif name == "pour"
      effect = PourEffect.new(ctx, {})
    elsif name == "slide"
      effect = SlideEffect.new(ctx, {})
    elsif name == "spotlights"
      effect = SpotlightsEffect.new(ctx, {})
    elsif name == "burn"
      effect = BurnEffect.new(ctx, {})
    elsif name == "orbittingvolley"
      effect = OrbittingvolleyEffect.new(ctx, {})
    elsif name == "print"
      effect = PrintEffect.new(ctx, {})
    elsif name == "fireworks"
      effect = FireworksEffect.new(ctx, {})
    elsif name == "colorshift"
      effect = ColorshiftEffect.new(ctx, {})
    elsif name == "binarypath"
      effect = BinarypathEffect.new(ctx, {})
    elsif name == "errorcorrect"
      effect = ErrorcorrectEffect.new(ctx, {})
    elsif name == "rings"
      effect = RingsEffect.new(ctx, {})
    elsif name == "swarm"
      effect = SwarmEffect.new(ctx, {})
    elsif name == "crumble"
      effect = CrumbleEffect.new(ctx, {})
    elsif name == "unstable"
      effect = UnstableEffect.new(ctx, {})
    elsif name == "laseretch"
      effect = LaseretchEffect.new(ctx, {})
    elsif name == "bubbles"
      effect = BubblesEffect.new(ctx, {})
    elsif name == "synthgrid"
      effect = SynthgridEffect.new(ctx, {})
    elsif name == "blackhole"
      effect = BlackholeEffect.new(ctx, {})
    elsif name == "vhstape"
      effect = VhstapeEffect.new(ctx, {})
    elsif name == "thunderstorm"
      effect = ThunderstormEffect.new(ctx, {})
    else
      effect = WipeEffect.new(ctx, {})
    end
    effect.build
    last = ctx.frame_cells
    loop do
      break if !gui.window_open?
      frame = effect.next_frame
      unless frame.nil?
        last = ctx.frame_cells
      end
      gui.draw_cells(last)
    end
  else
    engine = Engine.new(canvas, gui.rng)
    effect = Effects.build_legacy(name, engine)
    if effect.nil?
      gui.close
      puts("unknown effect: #{name}")
      return 1
    end
    last = []
    loop do
      break if !gui.window_open?
      draws = effect.next_frame
      last = draws unless draws.nil?
      cells = last.map do |d|
        fg = d[3]
        # legacy draws are 0-based top-down canvas cells; cells are 1-based
        # bottom-up terminal coordinates (offsets applied).
        r1 = canvas.top - d[0] + canvas.row_offset
        c1 = d[1] + 1 + canvas.col_offset
        if fg.nil?
          [r1, c1, d[2], 255, 255, 255]
        else
          [r1, c1, d[2], fg[0], fg[1], fg[2]]
        end
      end
      gui.draw_cells(cells)
    end
  end
  gui.close
  0
end

exit(main)
