# ttfx-rb entry point (compile root). Usage:
#   echo "hello" | ttfx-rb decrypt [--seed N] [decrypt options]
#   ttfx-rb --list
#   ttfx-rb --seed 42 --dump-frames --max-frames 12 --text hi decrypt
require "ttfx"

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
        puts("Error reading input file")
        exit(1)
      end
    end
  end
  # piped input only — never block on an interactive tty (mirrors ttfx)
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

def flag_set?(name)
  ARGV.include?(name)
end

# Non-negative int (mirrors parse_non_negative_int); nil when invalid.
def parse_nonneg_int(s)
  return nil unless s =~ /\A-?\d+\z/
  v = s.to_i
  return nil if v < 0
  v
end

# Positive float (mirrors parse_positive_float); nil when invalid.
def parse_positive_float(s)
  return nil unless s =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
  v = s.to_f
  return nil unless v > 0.0
  v
end

def float_error(s)
  if s =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
    "#{s.to_f} is not a valid value. Argument must be a float > 0."
  else
    "invalid float value: '#{s}'"
  end
end

# "a-b" with 0 < a <= b, else nil (mirrors parse_positive_int_range).
def parse_int_range(s)
  parts = s.split("-")
  return nil if parts.length != 2
  a = parts[0].to_i
  b = parts[1].to_i
  return nil unless parts[0] =~ /\A\d+\z/ && parts[1] =~ /\A\d+\z/
  return nil unless a > 0 && a <= b
  [a, b]
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
  if flag_set?("--list") || flag_set?("-l")
    Effects.names.each do |n|
      puts("#{n}: #{Effects::REGISTRY[n][2]}")
    end
    return 0
  end

  name = ARGV.find { |a| Effects::REGISTRY.key?(a) }
  seed_text = flag_value("--seed")
  seed = seed_text.nil? ? 12345 : seed_text.to_i
  rng = Rng.new(seed)
  # --random-effect wins over an explicit effect (mirrors ttfx); the
  # selection draw comes out of the same stream the engine then uses.
  if flag_set?("--random-effect") || flag_set?("-R")
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
    puts("usage: ttfx-rb [options] <effect>")
    puts("effects: #{Effects.names.join(', ')}")
    return 1
  end

  text = read_input
  if text.strip.empty?
    puts("NO INPUT.")
    return 1
  end

  if Effects.kind(name) == "faithful"
    opts = {}
    v = flag_values("--final-gradient-stops")
    opts["final_gradient_stops"] = v unless v.nil? || v.empty?
    v = flag_values("--final-gradient-steps")
    opts["final_gradient_steps"] = v.map { |x| x.to_i } unless v.nil? || v.empty?
    v = flag_value("--final-gradient-direction")
    unless v.nil?
      unless ["horizontal", "vertical", "diagonal", "radial"].include?(v)
        puts("invalid gradient direction: '#{v}'")
        return 1
      end
      opts["final_gradient_direction"] = v
    end
    anchors = ["n", "ne", "e", "se", "s", "sw", "w", "nw", "c"]
    act = flag_value("--anchor-canvas")
    unless act.nil?
      unless anchors.include?(act)
        puts("invalid anchor: '#{act}'")
        return 1
      end
    end
    atx = flag_value("--anchor-text")
    unless atx.nil?
      unless anchors.include?(atx)
        puts("invalid anchor: '#{atx}'")
        return 1
      end
    end
    tw = flag_value("--tab-width")
    tab_width = tw.nil? ? 4 : tw.to_i
    if tab_width < 1
      puts("#{tab_width} is not > 0")
      return 1
    end
    fr = flag_value("--frame-rate")
    fr = flag_value("--fps") if fr.nil?
    frame_rate = 60
    unless fr.nil?
      frame_rate = parse_nonneg_int(fr)
      if frame_rate.nil?
        if fr =~ /\A-?\d+\z/
          puts("#{fr.to_i} is not >= 0")
        else
          puts("invalid int value: '#{fr}'")
        end
        return 1
      end
    end
    ws = Terminal.size
    canvas = Canvas.new(ws[0], ws[1], text, tab_width, act || "sw", atx || "sw")
    ctx = EngineCtx.new(canvas, rng)
    ctx.frame_rate = frame_rate
    ctx.use_virtual_clock if flag_set?("--dump-frames")
    if name == "decrypt"
      v = flag_value("--typing-speed")
      opts["typing_speed"] = v.to_i unless v.nil?
      v = flag_values("--ciphertext-colors")
      opts["ciphertext_colors"] = v unless v.nil? || v.empty?
      effect = DecryptEffect.new(ctx, opts)
    elsif name == "waves"
      v = flag_values("--wave-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["wave_symbols"] = v
      end
      v = flag_values("--wave-gradient-stops")
      opts["wave_gradient_stops"] = v unless v.nil? || v.empty?
      v = flag_values("--wave-gradient-steps")
      opts["wave_gradient_steps"] = v.map { |x| x.to_i } unless v.nil? || v.empty?
      v = flag_value("--wave-count")
      opts["wave_count"] = v.to_i unless v.nil?
      v = flag_value("--wave-length")
      opts["wave_length"] = v.to_i unless v.nil?
      v = flag_value("--wave-direction")
      unless v.nil?
        unless WavesEffect::DIRECTIONS.include?(v)
          puts("invalid wave direction: '#{v}'")
          return 1
        end
        opts["wave_direction"] = v
      end
      v = flag_value("--wave-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["wave_easing"] = v
      end
      effect = WavesEffect.new(ctx, opts)
    elsif name == "rain"
      v = flag_values("--rain-colors")
      unless v.nil? || v.empty?
        bad = v.any? { |h| Color.from_hex(h).nil? }
        if bad
          puts("invalid color value")
          return 1
        end
        opts["rain_colors"] = v
      end
      v = flag_value("--movement-speed")
      unless v.nil?
        parts = v.split("-")
        if parts.length != 2
          puts("invalid range: '#{v}'")
          return 1
        end
        lo = parts[0].to_f
        hi = parts[1].to_f
        if !(lo > 0.0 && lo <= hi)
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["movement_speed"] = [lo, hi]
      end
      v = flag_values("--rain-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["rain_symbols"] = v
      end
      v = flag_value("--movement-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["movement_easing"] = v
      end
      effect = RainEffect.new(ctx, opts)
    elsif name == "wipe"
      v = flag_value("--wipe-direction")
      unless v.nil?
        unless WipeEffect::GROUPS.include?(v)
          puts("invalid character group: '#{v}'")
          return 1
        end
        opts["wipe_direction"] = v
      end
      v = flag_value("--wipe-delay")
      opts["wipe_delay"] = v.to_i unless v.nil?
      v = flag_value("--wipe-ease")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["wipe_ease"] = v
      end
      v = flag_value("--final-gradient-frames")
      opts["final_gradient_frames"] = v.to_i unless v.nil?
      if name == "wipe"
        effect = WipeEffect.new(ctx, opts)
      end
    elsif name == "beams"
      v = flag_values("--beam-row-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["beam_row_symbols"] = v
      end
      v = flag_values("--beam-column-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["beam_column_symbols"] = v
      end
      v = flag_value("--beam-delay")
      opts["beam_delay"] = v.to_i unless v.nil?
      v = flag_value("--beam-row-speed-range")
      unless v.nil?
        r = parse_int_range(v)
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["beam_row_speed_range"] = r
      end
      v = flag_value("--beam-column-speed-range")
      unless v.nil?
        r = parse_int_range(v)
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["beam_column_speed_range"] = r
      end
      v = flag_values("--beam-gradient-stops")
      opts["beam_gradient_stops"] = v unless v.nil? || v.empty?
      v = flag_values("--beam-gradient-steps")
      opts["beam_gradient_steps"] = v.map { |x| x.to_i } unless v.nil? || v.empty?
      v = flag_value("--beam-gradient-frames")
      opts["beam_gradient_frames"] = v.to_i unless v.nil?
      v = flag_value("--final-wipe-speed")
      opts["final_wipe_speed"] = v.to_i unless v.nil?
      effect = BeamsEffect.new(ctx, opts)
    elsif name == "matrix"
      v = flag_value("--highlight-color")
      unless v.nil?
        if Color.from_hex(v).nil?
          puts("invalid color value: '#{v}'")
          return 1
        end
        opts["highlight_color"] = v
      end
      v = flag_values("--rain-color-gradient")
      unless v.nil? || v.empty?
        bad = v.any? { |h| Color.from_hex(h).nil? }
        if bad
          puts("invalid color value")
          return 1
        end
        opts["rain_color_gradient"] = v
      end
      v = flag_values("--rain-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["rain_symbols"] = v
      end
      v = flag_value("--rain-fall-delay-range")
      unless v.nil?
        r = parse_int_range(v)
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["rain_fall_delay_range"] = r
      end
      v = flag_value("--rain-column-delay-range")
      unless v.nil?
        r = parse_int_range(v)
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["rain_column_delay_range"] = r
      end
      v = flag_value("--rain-time")
      opts["rain_time"] = v.to_i unless v.nil?
      v = flag_value("--symbol-swap-chance")
      unless v.nil?
        f = v.to_f
        if !(f > 0.0)
          puts("#{f} is not a valid value. Argument must be a float > 0.")
          return 1
        end
        opts["symbol_swap_chance"] = f
      end
      v = flag_value("--color-swap-chance")
      unless v.nil?
        f = v.to_f
        if !(f > 0.0)
          puts("#{f} is not a valid value. Argument must be a float > 0.")
          return 1
        end
        opts["color_swap_chance"] = f
      end
      v = flag_value("--resolve-delay")
      opts["resolve_delay"] = v.to_i unless v.nil?
      effect = MatrixEffect.new(ctx, opts)
    elsif name == "bouncyballs"
      v = flag_values("--ball-colors")
      unless v.nil? || v.empty?
        bad = v.any? { |h| Color.from_hex(h).nil? }
        if bad
          puts("invalid color value")
          return 1
        end
        opts["ball_colors"] = v
      end
      v = flag_values("--ball-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["ball_symbols"] = v
      end
      v = flag_value("--ball-delay")
      opts["ball_delay"] = v.to_i unless v.nil?
      v = flag_value("--movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["movement_speed"] = f
      end
      v = flag_value("--movement-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["movement_easing"] = v
      end
      effect = BouncyballsEffect.new(ctx, opts)
    elsif name == "sweep"
      v = flag_values("--sweep-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["sweep_symbols"] = v
      end
      v = flag_value("--first-sweep-direction")
      unless v.nil?
        unless WipeEffect::GROUPS.include?(v)
          puts("invalid character group: '#{v}'")
          return 1
        end
        opts["first_sweep_direction"] = v
      end
      v = flag_value("--second-sweep-direction")
      unless v.nil?
        unless WipeEffect::GROUPS.include?(v)
          puts("invalid character group: '#{v}'")
          return 1
        end
        opts["second_sweep_direction"] = v
      end
      effect = SweepEffect.new(ctx, opts)
    elsif name == "middleout"
      v = flag_value("--starting-color")
      unless v.nil?
        if Color.from_hex(v).nil?
          puts("invalid color value: '#{v}'")
          return 1
        end
        opts["starting_color"] = v
      end
      v = flag_value("--expand-direction")
      unless v.nil?
        unless ["vertical", "horizontal"].include?(v)
          puts("invalid choice: '#{v}' (choose from 'vertical', 'horizontal')")
          return 1
        end
        opts["expand_direction"] = v
      end
      v = flag_value("--center-movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["center_movement_speed"] = f
      end
      v = flag_value("--full-movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["full_movement_speed"] = f
      end
      v = flag_value("--center-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["center_easing"] = v
      end
      v = flag_value("--full-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["full_easing"] = v
      end
      effect = MiddleoutEffect.new(ctx, opts)
    elsif name == "smoke"
      v = flag_value("--starting-color")
      unless v.nil?
        if Color.from_hex(v).nil?
          puts("invalid color value: '#{v}'")
          return 1
        end
        opts["starting_color"] = v
      end
      v = flag_values("--smoke-symbols")
      unless v.nil? || v.empty?
        bad = v.any? { |s| s.length != 1 }
        if bad
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["smoke_symbols"] = v
      end
      v = flag_values("--smoke-gradient-stops")
      unless v.nil? || v.empty?
        bad = v.any? { |h| Color.from_hex(h).nil? }
        if bad
          puts("invalid color value")
          return 1
        end
        opts["smoke_gradient_stops"] = v
      end
      opts["use_whole_canvas"] = true if flag_set?("--use-whole-canvas")
      effect = SmokeEffect.new(ctx, opts)
    elsif name == "slice"
      v = flag_value("--slice-direction")
      unless v.nil?
        unless ["vertical", "horizontal", "diagonal"].include?(v)
          puts("invalid value '#{v}'")
          return 1
        end
        opts["slice_direction"] = v
      end
      v = flag_value("--movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["movement_speed"] = f
      end
      v = flag_value("--movement-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["movement_easing"] = v
      end
      effect = SliceEffect.new(ctx, opts)
    elsif name == "overflow"
      v = flag_values("--overflow-gradient-stops")
      opts["overflow_gradient_stops"] = v unless v.nil? || v.empty?
      v = flag_value("--overflow-cycles-range")
      unless v.nil?
        r = parse_int_range(v)
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["overflow_cycles_range"] = r
      end
      v = flag_value("--overflow-speed")
      opts["overflow_speed"] = v.to_i unless v.nil?
      effect = OverflowEffect.new(ctx, opts)
    elsif name == "pour"
      v = flag_value("--pour-direction")
      unless v.nil?
        unless PourEffect::DIRECTIONS.include?(v)
          puts("invalid choice: '#{v}' (choose from 'up', 'down', 'left', 'right')")
          return 1
        end
        opts["pour_direction"] = v
      end
      v = flag_value("--pour-speed")
      opts["pour_speed"] = v.to_i unless v.nil?
      v = flag_value("--movement-speed-range")
      unless v.nil?
        parts = v.split("-")
        r = nil
        if parts.length == 2 && parts[0] =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && parts[1] =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
          a = parts[0].to_f
          b = parts[1].to_f
          r = [a, b] if a > 0.0 && a <= b
        end
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["movement_speed_range"] = r
      end
      v = flag_value("--gap")
      opts["gap"] = v.to_i unless v.nil?
      v = flag_value("--starting-color")
      unless v.nil?
        if Color.from_hex(v).nil?
          puts("invalid color value: '#{v}'")
          return 1
        end
        opts["starting_color"] = v
      end
      v = flag_value("--movement-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["movement_easing"] = v
      end
      effect = PourEffect.new(ctx, opts)
    elsif name == "slide"
      v = flag_value("--movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["movement_speed"] = f
      end
      v = flag_value("--grouping")
      unless v.nil?
        unless SlideEffect::GROUPINGS.include?(v)
          puts("invalid choice: '#{v}' (choose from 'row', 'column', 'diagonal')")
          return 1
        end
        opts["grouping"] = v
      end
      v = flag_value("--gap")
      unless v.nil?
        g = parse_nonneg_int(v)
        if g.nil?
          puts("#{v} is not a valid value. Argument must be an int >= 0.")
          return 1
        end
        opts["gap"] = g
      end
      opts["reverse_direction"] = true if flag_set?("--reverse-direction")
      opts["merge"] = true if flag_set?("--merge")
      v = flag_value("--movement-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["movement_easing"] = v
      end
      effect = SlideEffect.new(ctx, opts)
    elsif name == "spotlights"
      v = flag_value("--beam-width-ratio")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["beam_width_ratio"] = f
      end
      v = flag_value("--beam-falloff")
      unless v.nil?
        ok = v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && v.to_f >= 0.0
        unless ok
          if v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
            puts("#{v.to_f} is not a valid value. Argument must be a float >= 0.")
          else
            puts("invalid float value: '#{v}'")
          end
          return 1
        end
        opts["beam_falloff"] = v.to_f
      end
      v = flag_value("--search-duration")
      opts["search_duration"] = v.to_i unless v.nil?
      v = flag_value("--search-speed-range")
      unless v.nil?
        parts = v.split("-")
        r = nil
        if parts.length == 2 && parts[0] =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && parts[1] =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
          a = parts[0].to_f
          b = parts[1].to_f
          r = [a, b] if a > 0.0 && a <= b
        end
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["search_speed_range"] = r
      end
      v = flag_value("--spotlight-count")
      opts["spotlight_count"] = v.to_i unless v.nil?
      effect = SpotlightsEffect.new(ctx, opts)
    elsif name == "burn"
      v = flag_value("--starting-color")
      unless v.nil?
        if Color.from_hex(v).nil?
          puts("invalid color value: '#{v}'")
          return 1
        end
        opts["starting_color"] = v
      end
      v = flag_values("--burn-colors")
      unless v.nil? || v.empty?
        bad = v.any? { |h| Color.from_hex(h).nil? }
        if bad
          puts("invalid color value")
          return 1
        end
        opts["burn_colors"] = v
      end
      v = flag_value("--smoke-chance")
      unless v.nil?
        ok = v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && v.to_f >= 0.0 && v.to_f <= 1.0
        unless ok
          if v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
            puts("#{v.to_f} is not a valid value. Argument must be a float 0 <= n <= 1.")
          else
            puts("invalid float value: '#{v}'")
          end
          return 1
        end
        opts["smoke_chance"] = v.to_f
      end
      effect = BurnEffect.new(ctx, opts)
    elsif name == "orbittingvolley"
      v = flag_value("--top-launcher-symbol")
      unless v.nil?
        if v.length != 1
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["top_launcher_symbol"] = v
      end
      v = flag_value("--right-launcher-symbol")
      unless v.nil?
        if v.length != 1
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["right_launcher_symbol"] = v
      end
      v = flag_value("--bottom-launcher-symbol")
      unless v.nil?
        if v.length != 1
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["bottom_launcher_symbol"] = v
      end
      v = flag_value("--left-launcher-symbol")
      unless v.nil?
        if v.length != 1
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["left_launcher_symbol"] = v
      end
      v = flag_value("--launcher-movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["launcher_movement_speed"] = f
      end
      v = flag_value("--character-movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["character_movement_speed"] = f
      end
      v = flag_value("--volley-size")
      unless v.nil?
        ok = v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && v.to_f >= 0.0 && v.to_f <= 1.0
        unless ok
          if v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
            puts("#{v.to_f} is not a valid value. Argument must be a float >= 0.")
          else
            puts("invalid float value: '#{v}'")
          end
          return 1
        end
        opts["volley_size"] = v.to_f
      end
      v = flag_value("--launch-delay")
      opts["launch_delay"] = v.to_i unless v.nil?
      v = flag_value("--character-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["character_easing"] = v
      end
      effect = OrbittingvolleyEffect.new(ctx, opts)
    elsif name == "print"
      v = flag_value("--print-head-return-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["print_head_return_speed"] = f
      end
      v = flag_value("--print-speed")
      opts["print_speed"] = v.to_i unless v.nil?
      v = flag_value("--print-head-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["print_head_easing"] = v
      end
      effect = PrintEffect.new(ctx, opts)
    elsif name == "fireworks"
      opts["explode_anywhere"] = true if flag_set?("--explode-anywhere")
      v = flag_values("--firework-colors")
      unless v.nil? || v.empty?
        bad = v.any? { |h| Color.from_hex(h).nil? }
        if bad
          puts("invalid color value")
          return 1
        end
        opts["firework_colors"] = v
      end
      v = flag_value("--firework-symbol")
      unless v.nil?
        if v.length != 1
          puts("invalid symbol argument must be a single character")
          return 1
        end
        opts["firework_symbol"] = v
      end
      v = flag_value("--firework-volume")
      unless v.nil?
        ok = v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && v.to_f >= 0.0 && v.to_f <= 1.0
        unless ok
          if v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
            puts("#{v.to_f} is not a valid value. Argument must be a float >= 0.")
          else
            puts("invalid float value: '#{v}'")
          end
          return 1
        end
        opts["firework_volume"] = v.to_f
      end
      v = flag_value("--launch-delay")
      opts["launch_delay"] = v.to_i unless v.nil?
      v = flag_value("--explode-distance")
      unless v.nil?
        ok = v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && v.to_f >= 0.0 && v.to_f <= 1.0
        unless ok
          if v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
            puts("#{v.to_f} is not a valid value. Argument must be a float >= 0.")
          else
            puts("invalid float value: '#{v}'")
          end
          return 1
        end
        opts["explode_distance"] = v.to_f
      end
      effect = FireworksEffect.new(ctx, opts)
    elsif name == "colorshift"
      v = flag_values("--gradient-stops")
      opts["gradient_stops"] = v unless v.nil? || v.empty?
      v = flag_values("--gradient-steps")
      opts["gradient_steps"] = v.map { |x| x.to_i } unless v.nil? || v.empty?
      v = flag_value("--gradient-frames")
      opts["gradient_frames"] = v.to_i unless v.nil?
      opts["no_travel"] = true if flag_set?("--no-travel")
      v = flag_value("--travel-direction")
      unless v.nil?
        unless ["horizontal", "vertical", "diagonal", "radial"].include?(v)
          puts("invalid gradient direction: '#{v}'")
          return 1
        end
        opts["travel_direction"] = v
      end
      opts["reverse_travel_direction"] = true if flag_set?("--reverse-travel-direction")
      opts["no_loop"] = true if flag_set?("--no-loop")
      v = flag_value("--cycles")
      opts["cycles"] = v.to_i unless v.nil?
      opts["skip_final_gradient"] = true if flag_set?("--skip-final-gradient")
      effect = ColorshiftEffect.new(ctx, opts)
    elsif name == "rings"
      effect = RingsEffect.new(ctx, opts)
    elsif name == "binarypath"
      v = flag_values("--binary-colors")
      opts["binary_colors"] = v unless v.nil? || v.empty?
      v = flag_value("--movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["movement_speed"] = f
      end
      v = flag_value("--active-binary-groups")
      unless v.nil?
        ok = v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && v.to_f >= 0.0 && v.to_f <= 1.0
        unless ok
          if v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
            puts("#{v.to_f} is not a valid value. Argument must be a float >= 0.")
          else
            puts("invalid float value: '#{v}'")
          end
          return 1
        end
        opts["active_binary_groups"] = v.to_f
      end
      effect = BinarypathEffect.new(ctx, opts)
    elsif name == "errorcorrect"
      v = flag_value("--error-pairs")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["error_pairs"] = f
      end
      v = flag_value("--swap-delay")
      opts["swap_delay"] = v.to_i unless v.nil?
      v = flag_value("--error-color")
      unless v.nil?
        if Color.from_hex(v).nil?
          puts("invalid color value: '#{v}'")
          return 1
        end
        opts["error_color"] = v
      end
      v = flag_value("--correct-color")
      unless v.nil?
        if Color.from_hex(v).nil?
          puts("invalid color value: '#{v}'")
          return 1
        end
        opts["correct_color"] = v
      end
      v = flag_value("--movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["movement_speed"] = f
      end
      effect = ErrorcorrectEffect.new(ctx, opts)
    elsif name == "swarm"
      effect = SwarmEffect.new(ctx, opts)
    elsif name == "crumble"
      effect = CrumbleEffect.new(ctx, opts)
    elsif name == "unstable"
      effect = UnstableEffect.new(ctx, opts)
    elsif name == "laseretch"
      effect = LaseretchEffect.new(ctx, opts)
    elsif name == "bubbles"
      effect = BubblesEffect.new(ctx, opts)
    elsif name == "synthgrid"
      effect = SynthgridEffect.new(ctx, opts)
    elsif name == "blackhole"
      effect = BlackholeEffect.new(ctx, opts)
    elsif name == "vhstape"
      effect = VhstapeEffect.new(ctx, opts)
    elsif name == "thunderstorm"
      effect = ThunderstormEffect.new(ctx, opts)
    elsif name == "highlight"
      v = flag_value("--highlight-brightness")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["highlight_brightness"] = f
      end
      v = flag_value("--highlight-direction")
      unless v.nil?
        unless WipeEffect::GROUPS.include?(v)
          puts("invalid character group: '#{v}'")
          return 1
        end
        opts["highlight_direction"] = v
      end
      v = flag_value("--highlight-width")
      opts["highlight_width"] = v.to_i unless v.nil?
      effect = HighlightEffect.new(ctx, opts)
    elsif name == "randomsequence"
      v = flag_value("--speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["speed"] = f
      end
      v = flag_value("--final-gradient-frames")
      opts["final_gradient_frames"] = v.to_i unless v.nil?
      effect = RandomsequenceEffect.new(ctx, opts)
    elsif name == "scattered"
      v = flag_value("--movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["movement_speed"] = f
      end
      v = flag_value("--movement-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["movement_easing"] = v
      end
      v = flag_value("--final-gradient-frames")
      opts["final_gradient_frames"] = v.to_i unless v.nil?
      effect = ScatteredEffect.new(ctx, opts)
    elsif name == "expand"
      v = flag_value("--expand-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["expand_easing"] = v
      end
      v = flag_value("--movement-speed")
      unless v.nil?
        f = parse_positive_float(v)
        if f.nil?
          puts(float_error(v))
          return 1
        end
        opts["movement_speed"] = f
      end
      effect = ExpandEffect.new(ctx, opts)
    elsif name == "spray"
      v = flag_value("--spray-position")
      unless v.nil?
        unless SprayEffect::POSITIONS.include?(v)
          puts("invalid choice: '#{v}' (choose from 'n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw', 'center')")
          return 1
        end
        opts["spray_position"] = v
      end
      v = flag_value("--spray-volume")
      unless v.nil?
        ok = v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && v.to_f > 0.0 && v.to_f <= 1.0
        unless ok
          if v =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
            puts("#{v.to_f} is not a valid value. Argument must be a float 0 < n <= 1.")
          else
            puts("invalid float value: '#{v}'")
          end
          return 1
        end
        opts["spray_volume"] = v.to_f
      end
      v = flag_value("--movement-speed-range")
      unless v.nil?
        parts = v.split("-")
        r = nil
        if parts.length == 2 && parts[0] =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/ && parts[1] =~ /\A-?(\d+\.?\d*|\.\d+)([eE]-?\d+)?\z/
          a = parts[0].to_f
          b = parts[1].to_f
          r = [a, b] if a > 0.0 && a <= b
        end
        if r.nil?
          puts("invalid range: '#{v}'")
          return 1
        end
        opts["movement_speed_range"] = r
      end
      v = flag_value("--movement-easing")
      unless v.nil?
        unless Easing.valid_name?(v)
          puts("invalid easing function: '#{v}'")
          return 1
        end
        opts["movement_easing"] = v
      end
      effect = SprayEffect.new(ctx, opts)
    end
    effect.build
    if flag_set?("--bench")
      # Throughput benchmark (chart methodology: pacing disabled, render
      # only): frames=N time_ms=X fps=Y on stderr.
      t0 = 0.0
      begin
        t0 = Time.now.to_f
      rescue StandardError
        t0 = 0.0
      end
      count = 0
      loop do
        break if effect.next_frame.nil?
        count += 1
      end
      dt = 0.0
      begin
        dt = Time.now.to_f - t0
      rescue StandardError
        dt = 0.0
      end
      ms = (dt * 1000.0).to_i
      fps = dt > 0.0 ? (count.to_f / dt).to_i : 0
      STDERR.puts("frames=#{count} time_ms=#{ms} fps=#{fps}")
      return 0
    end
    if flag_set?("--dump-frames")
      mf = flag_value("--max-frames")
      maxf = mf.nil? ? 0 : mf.to_i
      FaithfulRun.dump(ctx, effect, maxf)
    else
      FaithfulRun.live(ctx, effect)
    end
    return 0
  end

  ws = Terminal.size
  canvas = Canvas.new(ws[0], ws[1], text)
  engine = Engine.new(canvas, rng)
  effect = Effects.build_legacy(name, engine)
  if effect.nil?
    puts("unknown effect: #{name}")
    return 1
  end
  engine.run(effect)
  0
end

exit(main)
