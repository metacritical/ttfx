# Faithful slide (ttfx src/effects/slide.rs, old-engine semantics).
#
# Character groups slide in from outside the terminal along eased paths,
# released with a gap between groups. Fully deterministic (no RNG draws).
class SlideEffect
  GROUPINGS = ["row", "column", "diagonal"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @speed = o.fetch("movement_speed", 0.8)
    @grouping = o.fetch("grouping", "row")
    @gap_default = o.fetch("gap", 2)
    @reverse = o.fetch("reverse_direction", false)
    @merge = o.fetch("merge", false)
    @ease = o.fetch("movement_easing", "in_out_quad")
    stop_hex = o.fetch("final_gradient_stops", ["833ab4", "fd1d1d", "fcb045"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_frames = o.fetch("final_gradient_frames", 6)
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @active_groups = []
    @gap = 0
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    grouping = "row_top_to_bottom"
    grouping = "column_left_to_right" if @grouping == "column"
    grouping = "diagonal_top_left_to_bottom_right" if @grouping == "diagonal"
    groups = cv.grouped_ids(grouping)
    groups.each do |group|
      group.each do |id|
        @ctx.motion_new_path(id, "input_path", @speed, @ease, 0, false)
        a = @ctx.anim(id)
        @ctx.motion_add_waypoint(id, "input_path", a.input_col, a.input_row)
      end
    end
    gi = 0
    while gi < groups.length
      group = groups[gi].dup
      if @grouping == "row"
        sc = nil
        if @merge && gi % 2 == 0
          sc = cv.right + 1
        else
          groups[gi] = groups[gi].reverse
          sc = cv.left - 1
        end
        if @reverse && !@merge
          groups[gi] = groups[gi].reverse
          sc = cv.right + 1
        end
        groups[gi].each do |id|
          @ctx.motion_set_coordinate(id, sc, @ctx.anim(id).input_row)
        end
      elsif @grouping == "column"
        sr = nil
        if @merge && gi % 2 == 0
          sr = cv.bottom - 1
        else
          groups[gi] = groups[gi].reverse
          sr = cv.top + 1
        end
        if @reverse && !@merge
          groups[gi] = groups[gi].reverse
          sr = cv.bottom - 1
        end
        groups[gi].each do |id|
          @ctx.motion_set_coordinate(id, @ctx.anim(id).input_col, sr)
        end
      else
        last = @ctx.anim(group[group.length - 1])
        dist = last.input_row - (cv.bottom - 1)
        scol = last.input_col - dist
        srow = last.input_row - dist
        if @merge && gi % 2 == 0
          groups[gi] = groups[gi].reverse
          first = @ctx.anim(group[0])
          d2 = (cv.top + 1) - first.input_row
          scol = first.input_col + d2
          srow = first.input_row + d2
        end
        if @reverse && !@merge
          groups[gi] = groups[gi].reverse
          first = @ctx.anim(group[0])
          d2 = (cv.top + 1) - first.input_row
          scol = first.input_col + d2
          srow = first.input_row + d2
        end
        groups[gi].each do |id|
          @ctx.motion_set_coordinate(id, scol, srow)
        end
      end
      group.each do |id|
        a = @ctx.anim(id)
        final = mapping.get(a.input_col, a.input_row)
        @ctx.new_scene(id, "slide_#{id}")
        cg = Gradient.with_steps([@final_stops[0], final], 10, false)
        pairs = cg.spectrum.map { |c| [c, nil] }
        @ctx.apply_gradient(id, "slide_#{id}", [a.input_sym], @final_frames, pairs)
        @ctx.activate_scene(id, "slide_#{id}")
      end
      gi += 1
    end
    @pending = groups
    @active_groups = []
    @gap = 0
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @pending.empty? && @ctx.active_empty? && @active_groups.empty?
      if @gap == @gap_default && !@pending.empty?
        @active_groups.push(@pending.shift)
        @gap = 0
      elsif !@pending.empty?
        @gap += 1
      end
      @active_groups.each do |group|
        unless group.empty?
          id = group.shift
          @ctx.set_visible(id, true)
          @ctx.motion_activate_path(id, "input_path")
          @ctx.active_include(id)
        end
      end
      @active_groups = @active_groups.select { |g| !g.empty? }
      @ctx.update
      return @ctx.frame_string
    end
    nil
  end
end
