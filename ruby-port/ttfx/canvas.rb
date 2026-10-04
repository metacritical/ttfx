# Faithful animation character + canvas layout
# (ttfx src/engine/terminal.rs parse/layout + src/engine/canvas.rs).
#
# Plain-text path only (no ANSI sequences in input): tab expansion, trailing
# blank trim, trailing empty-row trim, 1-based bottom-up coordinates, blank
# filtering, nine-point text anchoring with floor-division centering, and
# in-canvas filtering. Canvas bounds are 1-based: columns 1..=right,
# rows 1..=top.

# One animatable character (legacy simplified effects use row/col/sym/fg).
class FxChar
  attr_accessor :row, :col, :sym, :fg

  def initialize(row, col, sym)
    @row = row
    @col = col
    @sym = sym
    @fg = nil
  end
end

# Per-character animation state for the faithful scene machine.
class CharAnim
  attr_accessor :id, :input_col, :input_row, :input_sym
  attr_accessor :visible, :scenes, :active, :cur_sym, :cur_fg
  attr_accessor :cur_col, :cur_row, :paths, :active_path
  attr_accessor :is_fill, :layer
  attr_accessor :links, :north, :east, :south, :west
  attr_accessor :uses_preexisting_colors

  def initialize(id, col, row, sym)
    @id = id
    @input_col = col
    @input_row = row
    @input_sym = sym
    @visible = false
    @scenes = {}
    @active = nil
    @cur_sym = sym
    @cur_fg = nil
    @cur_col = col
    @cur_row = row
    @paths = {}
    @active_path = nil
    @is_fill = false
    @layer = 0
    @links = []
    @north = nil
    @east = nil
    @south = nil
    @west = nil
    @uses_preexisting_colors = true
  end
end

class Canvas
  attr_reader :rows, :cols
  attr_reader :right, :top, :left, :bottom
  attr_reader :text_left, :text_right, :text_top, :text_bottom
  attr_reader :text_width, :text_height
  attr_reader :center_column, :center_row
  attr_reader :text_center_column, :text_center_row
  attr_reader :chars, :anims, :visible_left, :visible_right, :visible_top, :visible_bottom
  attr_reader :col_offset, :row_offset

  def initialize(rows, cols, text, tab_width = 4, anchor_canvas = "sw", anchor_text = "sw")
    @rows = rows
    @cols = cols
    @left = 1
    @bottom = 1
    # Canvas dimensions: input-sized, clamped to the terminal area.
    lines = layout_lines(text, tab_width)
    input_width = 0
    lines.each { |l| input_width = l.length if l.length > input_width }
    input_height = lines.length
    w = input_width < cols ? input_width : cols
    h = input_height < rows ? input_height : rows
    @right = w < 1 ? 1 : w
    @top = h < 1 ? 1 : h
    @center_column = floor_div(@right, 2)
    @center_column = @left if @center_column < @left
    @center_column += 1 if @right % 2 != 0 && @right > 1
    @center_row = floor_div(@top, 2)
    @center_row = @bottom if @center_row < @bottom
    @center_row += 1 if @top % 2 != 0 && @top > 1
    # Canvas offsets place the canvas inside the terminal area per the
    # canvas anchor (sw default = bottom-left, zero offsets).
    @col_offset = 0
    @row_offset = 0
    case anchor_canvas
    when "s", "n", "c"
      @col_offset = floor_div(cols, 2) - floor_div(@right, 2)
    when "se", "e", "ne"
      @col_offset = cols - @right
    end
    case anchor_canvas
    when "w", "e", "c"
      @row_offset = floor_div(rows, 2) - floor_div(@top, 2)
    when "nw", "n", "ne"
      @row_offset = rows - @top
    end
    vr = @right + @col_offset
    @visible_right = vr < cols ? vr : cols
    vl = @left + @col_offset
    @visible_left = vl > 1 ? vl : 1
    vt = @top + @row_offset
    @visible_top = vt < rows ? vt : rows
    vb = @bottom + @row_offset
    @visible_bottom = vb > 1 ? vb : 1
    build_characters(lines)
    anchor_text(anchor_text)
    # Upper-bound filter (mirrors setup_input_characters post-filter).
    # NOTE: @anims (the arena) is never compacted: ids are stable arena
    # indices like Rust's CharId slots; @kept selects the visible ones.
    @kept = @kept.select { |id| @anims[id].input_row <= @top && @anims[id].input_col <= @right }
    build_fills
    build_neighbor_map
    build_legacy_chars
  end

  def floor_div(a, b)
    q = a / b
    q -= 1 if a % b != 0 && (a < 0) != (b < 0)
    q
  end

  # Circle coordinates with terminal-cell aspect compensation, matching
  # utils::geometry::find_coords_on_circle. Unique order is angle order.
  def find_coords_on_circle(origin_col, origin_row, radius, limit, unique = true)
    return [] if radius == 0
    count = limit == 0 ? PyCompat.round_half_even(2.0 * Math::PI * radius) : limit
    seen = {}
    out = []
    count.times do |i|
      angle = (2.0 * Math::PI / count) * i
      xdiff = radius * Math.cos(angle)
      coord = [PyCompat.round_half_even(origin_col + 2.0 * xdiff),
               PyCompat.round_half_even(origin_row + radius * Math.sin(angle))]
      unless unique && seen[coord]
        out << coord
      end
      seen[coord] = true
    end
    out
  end

  # Tab expansion + trailing-blank trim + trailing empty-row trim.
  def layout_lines(text, tab_width)
    raw = text.split("\n")
    raw = [""] if raw.empty?
    rows = raw.map do |line|
      out = []
      line.each_char do |c|
        if c == "\t"
          need = tab_width - (out.length % tab_width)
          need.times { out.push(" ") }
        else
          out.push(c)
        end
      end
      while !out.empty? && out[out.length - 1] == " "
        out.pop
      end
      out
    end
    while !rows.empty? && rows[rows.length - 1].empty?
      rows.pop
    end
    rows = [[" "]] if rows.empty?
    rows
  end

  def build_characters(lines)
    @anims = []
    input_height = lines.length
    id = 0
    r = 0
    while r < lines.length
      line = lines[r]
      c = 0
      while c < line.length
        sym = line[c]
        unless sym == " "
          @anims.push(CharAnim.new(id, c + 1, input_height - r, sym))
          id += 1
        end
        c += 1
      end
      r += 1
    end
  end

  # Nine-point anchor with floor-division centering + in-canvas filter.
  def anchor_text(anchor)
    return if @anims.empty?
    input_width = 0
    input_height = 0
    @anims.each do |a|
      input_width = a.input_col if a.input_col > input_width
      input_height = a.input_row if a.input_row > input_height
    end
    width = @right
    height = @top
    col_delta = 0
    row_delta = 0
    if input_width != width
      case anchor
      when "s", "n", "c"
        col_delta = @center_column - floor_div(input_width, 2)
      when "se", "e", "ne"
        col_delta = @right - input_width
      else
        col_delta = @left - 1
      end
    end
    if input_height != height
      case anchor
      when "w", "e", "c"
        row_delta = @center_row - floor_div(input_height, 2)
      when "nw", "n", "ne"
        row_delta = @top - input_height
      else
        row_delta = @bottom - 1
      end
    end
    @anims.each do |a|
      a.input_col += col_delta
      a.input_row += row_delta
    end
    @kept = @anims.select do |a|
      a.input_col >= @left && a.input_col <= @right && a.input_row >= @bottom && a.input_row <= @top
    end.map { |a| a.id }
    raise "all input characters fall outside the canvas after anchoring" if @kept.empty?
    first = @anims[@kept[0]]
    @text_left = first.input_col
    @text_right = first.input_col
    @text_top = first.input_row
    @text_bottom = first.input_row
    @kept.each do |id|
      a = @anims[id]
      @text_left = a.input_col if a.input_col < @text_left
      @text_right = a.input_col if a.input_col > @text_right
      @text_top = a.input_row if a.input_row > @text_top
      @text_bottom = a.input_row if a.input_row < @text_bottom
    end
    @text_width = @text_right - @text_left + 1
    @text_width = 1 if @text_width < 1
    @text_height = @text_top - @text_bottom + 1
    @text_height = 1 if @text_height < 1
    @text_center_row = @text_bottom + floor_div(@text_top - @text_bottom, 2)
    @text_center_column = @text_left + floor_div(@text_right - @text_left, 2)
  end

  # TopToBottomLeftToRight: (-row, column); coords unique so sort is total.
  def ordered_ids(ids = nil)
    list = ids.nil? ? @kept : ids
    list.sort_by do |id|
      a = @anims[id]
      [-a.input_row, a.input_col]
    end
  end

  # Fill characters for every unoccupied canvas cell (row-major from
  # (1,1)), mirroring Terminal._make_fill_characters. They extend the arena
  # past the input characters; effects opt in via the *_all id lists.
  def build_fills
    @fills = []
    occupied = {}
    @kept.each do |id|
      a = @anims[id]
      occupied[a.input_row * 1000000 + a.input_col] = true
    end
    r = 1
    while r <= @top
      c = 1
      while c <= @right
        unless occupied[r * 1000000 + c]
          id = @anims.length
          f = CharAnim.new(id, c, r, " ")
          f.is_fill = true
          f.uses_preexisting_colors = false
          @anims.push(f)
          @fills.push(id)
        end
        c += 1
      end
      r += 1
    end
  end

  def kept_anims
    @kept.map { |id| @anims[id] }
  end

  # Coordinate -> arena id over kept inputs + fills (dense grid).
  def build_neighbor_map
    @coord_map = {}
    (@kept + @fills).each do |id|
      a = @anims[id]
      @coord_map[a.input_row * 1000000 + a.input_col] = id
    end
    (@kept + @fills).each do |id|
      a = @anims[id]
      c = a.input_col
      r = a.input_row
      a.north = @coord_map[(r + 1) * 1000000 + c]
      a.east = @coord_map[r * 1000000 + (c + 1)]
      a.south = @coord_map[(r - 1) * 1000000 + c]
      a.west = @coord_map[r * 1000000 + (c - 1)]
    end
  end

  def char_by_coord(col, row)
    return nil if @coord_map.nil?
    @coord_map[row * 1000000 + col]
  end

  # Input characters plus fills (beams-style full-canvas effects).
  def render_anims
    @kept.map { |id| @anims[id] } + @fills.map { |id| @anims[id] }
  end

  def all_ids
    @kept + @fills
  end

  # Character grouping for wipe-style reveals (mirrors
  # get_characters_grouped; dense center path — sparse distances are
  # unreachable for plain in-canvas input).
  def grouped_ids(grouping, ids = nil)
    list = ids.nil? ? @kept : ids
    sorted = list.sort_by do |id|
      a = @anims[id]
      [a.input_row, a.input_col]
    end
    case grouping
    when "column_left_to_right"
      buckets(sorted, 0, @right) { |id| @anims[id].input_col }
    when "column_right_to_left"
      buckets(sorted, 0, @right) { |id| @anims[id].input_col }.reverse
    when "row_bottom_to_top"
      buckets(sorted, 0, @top) { |id| @anims[id].input_row }
    when "row_top_to_bottom"
      buckets(sorted, 0, @top) { |id| @anims[id].input_row }.reverse
    when "diagonal_bottom_left_to_top_right"
      buckets(sorted, 0, @top + @right) { |id| @anims[id].input_row + @anims[id].input_col }
    when "diagonal_top_right_to_bottom_left"
      buckets(sorted, 0, @top + @right) { |id| @anims[id].input_row + @anims[id].input_col }.reverse
    when "diagonal_top_left_to_bottom_right"
      buckets(sorted, @left - @top, @right - @bottom) { |id| @anims[id].input_col - @anims[id].input_row }
    when "diagonal_bottom_right_to_top_left"
      buckets(sorted, @left - @top, @right - @bottom) { |id| @anims[id].input_col - @anims[id].input_row }.reverse
    when "center_to_outside", "outside_to_center"
      cc = @text_center_column
      cr = @text_center_row
      maxd = 0
      sorted.each do |id|
        d = (@anims[id].input_col - cc).abs + (@anims[id].input_row - cr).abs
        maxd = d if d > maxd
      end
      groups = buckets(sorted, 0, maxd) do |id|
        (@anims[id].input_col - cc).abs + (@anims[id].input_row - cr).abs
      end
      grouping == "outside_to_center" ? groups.reverse : groups
    else
      raise "invalid character group: '#{grouping}'"
    end
  end

  def buckets(ids, first_key, last_key)    return [] if first_key > last_key
    count = last_key - first_key + 1
    bk = Array.new(count) { [] }
    ids.each do |id|
      k = yield(id)
      bk[k - first_key].push(id) if k >= first_key && k <= last_key
    end
    bk.select { |b| !b.empty? }
  end

  def char_count
    @kept.length
  end

  def random_column(rng, within_text)
    if within_text
      rng.randint(@text_left, @text_right)
    else
      rng.randint(@left, @right)
    end
  end

  def random_row(rng, within_text)
    if within_text
      rng.randint(@text_bottom, @text_top)
    else
      rng.randint(@bottom, @top)
    end
  end

  # Random coord; outside_scope picks one cell past an edge. The RNG call
  # order (above, below, left, right, then choice) is part of the contract.
  def random_coord(rng, outside_scope, within_text)
    if outside_scope
      above = [random_column(rng, false), @top + 1]
      below = [random_column(rng, false), @bottom - 1]
      left = [@left - 1, random_row(rng, false)]
      right = [@right + 1, random_row(rng, false)]
      return rng.choice([above, below, left, right])
    end
    [random_column(rng, within_text), random_row(rng, within_text)]
  end

  # ---- legacy compat (simplified effects): 0-based FxChar view ----
  def build_legacy_chars
    @chars = @kept.map do |id|
      a = @anims[id]
      FxChar.new(@top - a.input_row, a.input_col - 1, a.input_sym)
    end
    # legacy text metrics in 0-based display space
    @legacy_left = @text_left - 1
    @legacy_top = @top - @text_top
  end

  def text_rows
    []
  end
end
