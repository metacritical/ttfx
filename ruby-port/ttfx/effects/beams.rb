# Faithful beams (ttfx src/effects/beams.rs, old-engine semantics).
#
# Row and column groups sweep beam symbols across the whole canvas
# (input + fill characters); a final diagonal wipe brightens each input
# character into its final gradient color.
class BeamGroup
  attr_accessor :chars, :dir, :speed, :counter

  def initialize(chars, dir, speed)
    @chars = chars
    @dir = dir
    @speed = speed
    @counter = 0.0
  end
end

class BeamsEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @row_symbols = o.fetch("beam_row_symbols", ["\u2582", "\u2581", "_"])
    @col_symbols = o.fetch("beam_column_symbols", ["\u258c", "\u258d", "\u258e", "\u258f"])
    @delay_default = o.fetch("beam_delay", 6)
    @row_speed = o.fetch("beam_row_speed_range", [15, 60])
    @col_speed = o.fetch("beam_column_speed_range", [9, 15])
    beam_stop_hex = o.fetch("beam_gradient_stops", ["ffffff", "00D1FF", "8A008A"])
    @beam_steps = o.fetch("beam_gradient_steps", [2, 6])
    @beam_frames = o.fetch("beam_gradient_frames", 2)
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "ffffff"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_frames = o.fetch("final_gradient_frames", 4)
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @wipe_speed = o.fetch("final_wipe_speed", 3)
    @beam_stops = beam_stop_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @active_groups = []
    @final_map = {}
    @wipe_groups = []
    @delay = 0
    @phase = "beams"
  end

  def make_group(chars, dir)
    if dir == "row"
      lo = @row_speed[0]
      hi = @row_speed[1]
    else
      lo = @col_speed[0]
      hi = @col_speed[1]
    end
    speed = @ctx.rng.randint(lo, hi).to_f * 0.1
    sorted = chars.sort_by do |id|
      a = @ctx.anim(id)
      dir == "row" ? a.input_col : a.input_row
    end
    sorted = sorted.reverse if @ctx.rng.choice([true, false])
    BeamGroup.new(sorted, dir, speed)
  end

  def build
    cv = @ctx.canvas
    @wipe_groups = cv.grouped_ids("diagonal_top_left_to_bottom_right")
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    all = cv.all_ids
    order = cv.ordered_ids(all)
    order.each do |id|
      a = @ctx.anim(id)
      if a.is_fill
        @final_map[id] = [[0, 0, 0], nil]
      else
        @final_map[id] = [mapping.get(a.input_col, a.input_row), nil]
      end
    end
    bgrad = Gradient.build(@beam_stops, @beam_steps, false, false)
    groups = []
    cv.grouped_ids("row_top_to_bottom", all).each do |row|
      groups.push(make_group(row, "row"))
    end
    cv.grouped_ids("column_left_to_right", all).each do |col|
      groups.push(make_group(col, "column"))
    end
    groups.each do |g|
      next unless g.dir == "row"
      g.chars.each do |id|
        a = @ctx.anim(id)
        @ctx.new_scene(id, "beam_row")
        @ctx.new_scene(id, "beam_column")
        @ctx.new_scene(id, "brighten")
        rpairs = bgrad.spectrum.map { |c| [c, nil] }
        @ctx.apply_gradient(id, "beam_row", @row_symbols, @beam_frames, rpairs)
        @ctx.apply_gradient(id, "beam_column", @col_symbols, @beam_frames, rpairs)
        final = @final_map[id][0]
        if final.nil?
          @ctx.add_frame(id, "beam_row", a.input_sym, 2, nil)
          @ctx.add_frame(id, "beam_column", a.input_sym, 2, nil)
        else
          faded = Color.adjust_brightness(final, 0.3)
          fg = Gradient.with_steps([final, faded], 10, false)
          fpairs = fg.spectrum.map { |c| [c, nil] }
          @ctx.apply_gradient(id, "beam_row", [a.input_sym], 2, fpairs)
          @ctx.apply_gradient(id, "beam_column", [a.input_sym], 2, fpairs)
        end
        if final.nil?
          @ctx.add_frame(id, "brighten", a.input_sym, @final_frames, nil)
        else
          faded = Color.adjust_brightness(final, 0.3)
          bg = Gradient.with_steps([faded, final], 10, false)
          bpairs = bg.spectrum.map { |c| [c, nil] }
          @ctx.apply_gradient(id, "brighten", [a.input_sym], @final_frames, bpairs)
        end
      end
    end
    @pending = groups
    @ctx.rng.shuffle(@pending)
  end

  def get_next_character(group)
    group.counter -= 1.0
    id = group.chars.shift
    a = @ctx.anim(id)
    ret = nil
    unless a.active.nil?
      @ctx.reset_scene(id, a.active)
    else
      @ctx.set_visible(id, true)
      ret = id
    end
    if group.dir == "row"
      @ctx.activate_scene(id, "beam_row")
    else
      @ctx.activate_scene(id, "beam_column")
    end
    ret
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    if @phase != "complete" || !@ctx.active_empty?
      if @phase == "beams"
        if @delay == 0
          unless @pending.empty?
            n = @ctx.rng.randint(1, 5)
            n.times do
              break if @pending.empty?
              @active_groups.push(@pending.shift)
            end
          end
          @delay = @delay_default
        else
          @delay -= 1
        end
        @active_groups.each do |group|
          group.counter += group.speed
          count = group.counter.to_i
          if count > 1
            count.times do
              break if group.chars.empty?
              cid = get_next_character(group)
              @ctx.active_include(cid) unless cid.nil?
            end
          end
        end
        @active_groups = @active_groups.select { |g| !g.chars.empty? }
        if @pending.empty? && @active_groups.empty? && @ctx.active_empty?
          @phase = "final_wipe"
        end
      elsif @phase == "final_wipe"
        unless @wipe_groups.empty?
          @wipe_speed.times do
            break if @wipe_groups.empty?
            @wipe_groups.shift.each do |id|
              @ctx.activate_scene(id, "brighten")
              @ctx.set_visible(id, true)
              @ctx.active_include(id)
            end
          end
        else
          @phase = "complete"
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
