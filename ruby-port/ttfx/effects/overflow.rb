# Faithful overflow (ttfx src/effects/overflow.rs, old-engine semantics).
#
# Shuffled copies of each row scroll the terminal upward through an
# overflow gradient; the final ordered rows then scroll up and settle into
# the final gradient. Appends arena characters mid-build like Rust.
class OverflowEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    stop_hex = o.fetch("overflow_gradient_stops", ["f2ebc0", "8dbfb3", "f2ebc0"])
    cyc = o.fetch("overflow_cycles_range", [2, 4])
    @cyc_lo = cyc[0]
    @cyc_hi = cyc[1]
    @speed = o.fetch("overflow_speed", 3)
    final_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @overflow_stops = stop_hex.map { |h| Color.from_hex(h) }
    @final_stops = final_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @active_rows = []
    @final_map = {}
    @delay = 0
    @overflow_gradient = nil
  end

  def row_move_up(chars)
    chars.each do |id|
      a = @ctx.anim(id)
      @ctx.motion_set_coordinate(id, a.cur_col, a.cur_row + 1)
    end
  end

  def row_setup(chars)
    chars.each do |id|
      a = @ctx.anim(id)
      @ctx.motion_set_coordinate(id, a.input_col, 0)
    end
  end

  def row_set_color(chars, fg)
    chars.each do |id|
      a = @ctx.anim(id)
      @ctx.set_appearance(id, a.input_sym, fg)
    end
  end

  def row_head(chars)
    @ctx.anim(chars[0]).cur_row
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    black = [0, 0, 0]
    all = cv.all_ids
    order = cv.ordered_ids(all)
    order.each do |id|
      a = @ctx.anim(id)
      @final_map[id] = mapping.get(a.input_col, a.input_row) || black
    end
    rows = cv.grouped_ids("row_top_to_bottom")
    if @cyc_hi > 0
      n = @ctx.rng.randint(@cyc_lo, @cyc_hi)
      n.times do
        @ctx.rng.shuffle(rows)
        rows.each do |row|
          copies = []
          row.each do |id|
            a = @ctx.anim(id)
            cid = @ctx.add_character(a.input_sym, a.input_col, a.input_row)
            @ctx.anim(cid).uses_preexisting_colors = true
            copies.push(cid)
          end
          @pending.push([copies, false])
        end
      end
    end
    cv.grouped_ids("row_top_to_bottom", all).each do |row|
      row.each do |id|
        a = @ctx.anim(id)
        @ctx.set_appearance(id, a.input_sym, @final_map[id])
      end
      @pending.push([row, true])
    end
    @delay = 0
    denom = @overflow_stops.length - 1
    denom = 1 if denom < 1
    steps = cv.top / denom
    steps = 1 if steps < 1
    @overflow_gradient = Gradient.with_steps(@overflow_stops, steps, false)
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @pending.empty?
      if @delay == 0
        spec = @overflow_gradient.spectrum
        n = @ctx.rng.randint(1, @speed)
        n.times do
          break if @pending.empty?
          @active_rows.each do |row|
            chars = row[0]
            final = row[1]
            row_move_up(chars)
            unless final
              idx = row_head(chars)
              idx = spec.length - 1 if idx > spec.length - 1
              row_set_color(chars, spec[idx])
            end
          end
          chars, final = @pending.shift
          row_setup(chars)
          row_move_up(chars)
          row_set_color(chars, spec[0]) unless final
          chars.each { |id| @ctx.set_visible(id, true) }
          @active_rows.push([chars, final])
        end
        @delay = @ctx.rng.randint(0, 3)
      else
        @delay -= 1
      end
      top = @ctx.canvas.top
      @active_rows = @active_rows.select do |row|
        row_head(row[0]) <= top
      end
      @ctx.update
      return @ctx.frame_string
    end
    nil
  end
end
