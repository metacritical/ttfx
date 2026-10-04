# Python-compat helpers (ttfx src/utils/pycompat.rs).
module PyCompat
  # Python round(): banker's rounding to Integer.
  def self.round_half_even(x)
    f = x.floor
    d = x - f
    return f if d < 0.5
    return f + 1 if d > 0.5
    (f % 2 == 0) ? f : f + 1
  end
end

# Faithful RGB colors + floor-division gradients (ttfx src/utils/graphics.rs).
#
# Colors are [r, g, b] integer arrays. The Gradient spectrum is NOT float
# lerp: channel deltas use integer floor division and the exact end stop is
# appended per pair. Coordinate mapping and fraction lookup replicate the
# boundary semantics exactly (first i in 1..=len with fraction <= i/len).
module Color
  # ttfx default gradient endpoints (final_gradient_stops defaults)
  A = [97, 214, 241].freeze
  B = [168, 102, 241].freeze

  HEXDIGITS = "0123456789abcdef"

  def self.hex_val(c)
    case c
    when "0" then 0
    when "1" then 1
    when "2" then 2
    when "3" then 3
    when "4" then 4
    when "5" then 5
    when "6" then 6
    when "7" then 7
    when "8" then 8
    when "9" then 9
    when "a", "A" then 10
    when "b", "B" then 11
    when "c", "C" then 12
    when "d", "D" then 13
    when "e", "E" then 14
    when "f", "F" then 15
    else -1
    end
  end

  def self.hex2(s)
    h = hex_val(s[0, 1])
    l = hex_val(s[1, 1])
    return nil if h < 0 || l < 0
    h * 16 + l
  end

  # from_hex: 6 digits (a 7th is accepted, first six parsed — upstream quirk).
  # Returns [r,g,b] or nil.
  def self.from_hex(hex)
    s = hex
    s = s[1, s.length - 1] if s[0, 1] == "#"
    return nil unless s.length == 6 || s.length == 7
    r = hex2(s[0, 2])
    g = hex2(s[2, 2])
    b = hex2(s[4, 2])
    return nil if r.nil? || g.nil? || b.nil?
    [r, g, b]
  end

  def self.hex_digit(v)
    HEXDIGITS[v & 15, 1]
  end

  def self.to_hex(c)
    hex_digit(c[0] >> 4) + hex_digit(c[0]) + hex_digit(c[1] >> 4) + hex_digit(c[1]) + hex_digit(c[2] >> 4) + hex_digit(c[2])
  end

  def self.clamp(v)
    return 0 if v < 0
    return 255 if v > 255
    v
  end

  def self.hue_to_rgb(ls, ci, h)
    h += 1.0 if h < 0.0
    h -= 1.0 if h > 1.0
    return ls + (ci - ls) * 6.0 * h if h < 1.0 / 6.0
    return ci if h < 1.0 / 2.0
    if h < 2.0 / 3.0
      return ls + (ci - ls) * (2.0 / 3.0 - h) * 6.0
    end
    ls
  end

  # adjust_color_brightness: HSL lightness scaled by the factor.
  def self.adjust_brightness(c, brightness)
    nr = c[0].to_f / 255.0
    ng = c[1].to_f / 255.0
    nb = c[2].to_f / 255.0
    mx = nr
    mx = ng if ng > mx
    mx = nb if nb > mx
    mn = nr
    mn = ng if ng < mn
    mn = nb if nb < mn
    light = (mx + mn) / 2.0
    hue = 0.0
    sat = 0.0
    unless mx == mn
      diff = mx - mn
      if light > 0.5
        sat = diff / (2.0 - mx - mn)
      else
        sat = diff / (mx + mn)
      end
      if mx == nr
        hue = (ng - nb) / diff
        hue += 6.0 if ng < nb
      elsif mx == ng
        hue = (nb - nr) / diff + 2.0
      else
        hue = (nr - ng) / diff + 4.0
      end
      hue /= 6.0
    end
    light = light * brightness
    light = 1.0 if light > 1.0
    light = 0.0 if light < 0.0
    if sat == 0.0
      r = light
      g = light
      b = light
    else
      ci = 0.0
      if light < 0.5
        ci = light * (1.0 + sat)
      else
        ci = light + sat - light * sat
      end
      ls = 2.0 * light - ci
      r = hue_to_rgb(ls, ci, hue + 1.0 / 3.0)
      g = hue_to_rgb(ls, ci, hue)
      b = hue_to_rgb(ls, ci, hue - 1.0 / 3.0)
    end
    [PyCompat.round_half_even(r * 255.0), PyCompat.round_half_even(g * 255.0), PyCompat.round_half_even(b * 255.0)]
  end

  def self.fg(c)
    "\e[38;2;#{c[0]};#{c[1]};#{c[2]}m"
  end

  def self.fg_gray(level)
    [level, level, level]
  end

  RESET = "\e[0m"

  # ---- legacy compat (simplified effects) ----
  def self.lerp(c1, c2, t)
    r = c1[0] + ((c2[0] - c1[0]) * t).to_i
    g = c1[1] + ((c2[1] - c1[1]) * t).to_i
    b = c1[2] + ((c2[2] - c1[2]) * t).to_i
    [r, g, b]
  end

  def self.gradient(t)
    t = 0.0 if t < 0.0
    t = 1.0 if t > 1.0
    lerp(A, B, t)
  end

  def self.scale(c, f)
    [
      (c[0].to_f * f).to_i,
      (c[1].to_f * f).to_i,
      (c[2].to_f * f).to_i
    ]
  end
end

class Gradient
  attr_reader :spectrum

  def initialize(spectrum)
    @spectrum = spectrum
  end

  # stops: array of [r,g,b]; steps: array of ints.
  def self.build(stops, steps, steps_was_int, do_loop)
    raise "At least one stop must be provided." if stops.empty?
    if steps_was_int
      steps.each do |st|
        raise "Steps must be greater than 0." if st < 1
      end
    end
    if stops.length == 1
      spec = []
      i = 0
      while i < steps[0]
        spec.push([stops[0][0], stops[0][1], stops[0][2]])
        i += 1
      end
      return Gradient.new(spec)
    end
    sts = stops.map { |c| [c[0], c[1], c[2]] }
    sts.push([stops[0][0], stops[0][1], stops[0][2]]) if do_loop
    pair_count = sts.length - 1
    stps = steps[0, pair_count] || []
    stps = stps.dup
    while stps.length < pair_count
      stps.push(stps[stps.length - 1])
    end
    spec = []
    p = 0
    while p < pair_count
      sc = stps[p]
      raise "Invalid steps: #{sc} | Steps must be greater than 0." if sc < 1
      s = sts[p]
      e = sts[p + 1]
      # Ruby integer / is already floor division (Python // semantics).
      dr = (e[0] - s[0]) / sc
      dg = (e[1] - s[1]) / sc
      db = (e[2] - s[2]) / sc
      i = spec.empty? ? 0 : 1
      while i < sc
        spec.push([Color.clamp(s[0] + dr * i), Color.clamp(s[1] + dg * i), Color.clamp(s[2] + db * i)])
        i += 1
      end
      spec.push([e[0], e[1], e[2]])
      p += 1
    end
    Gradient.new(spec)
  end

  def self.with_steps(stops, steps, do_loop)
    build(stops, [steps], true, do_loop)
  end

  # First i in 1..=len with fraction <= i/len (boundary-exact).
  def color_at_fraction(fraction)
    raise "Fraction must be 0 <= fraction <= 1." unless fraction >= 0.0 && fraction <= 1.0
    len = @spectrum.length
    idx = (fraction * len.to_f).to_i
    idx = len - 1 if idx > len - 1
    while idx > 0 && fraction <= idx.to_f / len.to_f
      idx -= 1
    end
    while idx + 1 < len && fraction > (idx + 1).to_f / len.to_f
      idx += 1
    end
    @spectrum[idx]
  end

  # Normalized distance from center (radial gradient fraction).
  def self.radial_fraction(bottom, top, left, right, col, row)
    yoff = bottom - 1
    xoff = left - 1
    rw = (right - xoff).to_f
    th = (top - yoff).to_f
    cx = rw / 2.0
    cy = th / 2.0
    c = (col - xoff).to_f
    r = (row - yoff).to_f
    maxd = (rw ** 2.0 + (th * 2.0) ** 2.0) ** 0.5
    dist = ((c - cx) ** 2.0 + ((r - cy) * 2.0) ** 2.0) ** 0.5
    dist / (maxd / 2.0)
  end

  def radial_fraction(bottom, top, left, right, col, row)
    Gradient.radial_fraction(bottom, top, left, right, col, row)
  end

  # Coordinate -> color mapping over the inclusive coord rectangle.
  # direction: "vertical" | "horizontal" | "diagonal" | "radial".
  def coord_map(min_row, max_row, min_col, max_col, direction)
    raise "max_row and max_column must be greater than 0." if max_row < 1 || max_col < 1
    raise "min must be <= max." if min_row > max_row || min_col > max_col
    row_off = min_row - 1
    col_off = min_col - 1
    column_major = direction == "horizontal"
    width = max_col - min_col + 1
    height = max_row - min_row + 1
    colors = []
    if direction == "vertical"
      r = min_row
      while r <= max_row
        frac = (r - row_off).to_f / (max_row - row_off).to_f
        c = color_at_fraction(frac)
        col = min_col
        while col <= max_col
          colors.push(c)
          col += 1
        end
        r += 1
      end
    elsif direction == "horizontal"
      col = min_col
      while col <= max_col
        frac = (col - col_off).to_f / (max_col - col_off).to_f
        c = color_at_fraction(frac)
        r = min_row
        while r <= max_row
          colors.push(c)
          r += 1
        end
        col += 1
      end
    elsif direction == "diagonal"
      r = min_row
      while r <= max_row
        col = min_col
        while col <= max_col
          frac = ((r - row_off) * 2 + (col - col_off)).to_f / ((max_row - row_off) * 2 + (max_col - col_off)).to_f
          colors.push(color_at_fraction(frac))
          col += 1
        end
        r += 1
      end
    elsif direction == "radial"
      r = min_row
      while r <= max_row
        col = min_col
        while col <= max_col
          colors.push(color_at_fraction(radial_fraction(min_row, max_row, min_col, max_col, col, r)))
          col += 1
        end
        r += 1
      end
    else
      raise "Unsupported gradient direction: #{direction}"
    end
    GradientMap.new(min_row, min_col, width, height, column_major, colors)
  end
end

# Insertion-ordered Coord -> Color lookup over a dense rectangle.
class GradientMap
  def initialize(min_row, min_col, width, height, column_major, colors)
    @min_row = min_row
    @min_col = min_col
    @width = width
    @height = height
    @column_major = column_major
    @colors = colors
  end

  # coord as [column, row]; returns color or nil when outside.
  def get(col, row)
    c = col - @min_col
    r = row - @min_row
    return nil if c < 0 || r < 0 || c >= @width || r >= @height
    idx = @column_major ? c * @height + r : r * @width + c
    @colors[idx]
  end
end
