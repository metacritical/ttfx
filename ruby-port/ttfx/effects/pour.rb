# Faithful pour (ttfx src/effects/pour.rs, old-engine semantics).
#
# Characters pour in from an edge along eased paths, released group by
# group (alternating direction) with a gap between pours, cross-fading
# from white into the final gradient.
class PourEffect
  DIRECTIONS = ["up", "down", "left", "right"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @direction = o.fetch("pour_direction", "down")
    @pour_speed = o.fetch("pour_speed", 2)
    @speed_range = o.fetch("movement_speed_range", [0.4, 0.6])
    @gap_default = o.fetch("gap", 1)
    @starting = Color.from_hex(o.fetch("starting_color", "ffffff"))
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_frames = o.fetch("final_gradient_frames", 6)
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @ease = o.fetch("movement_easing", "in_quad")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending_groups = []
    @current_group = []
    @gap = 0
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    grouping = "row_bottom_to_top"
    grouping = "row_top_to_bottom" if @direction == "up"
    grouping = "column_left_to_right" if @direction == "left"
    grouping = "column_right_to_left" if @direction == "right"
    groups = cv.grouped_ids(grouping)
    gi = 0
    groups.each do |group|
      group.each do |id|
        a = @ctx.anim(id)
        @ctx.set_visible(id, false)
        if @direction == "down"
          scol = a.input_col
          srow = cv.top
        elsif @direction == "up"
          scol = a.input_col
          srow = cv.bottom
        elsif @direction == "left"
          scol = cv.right
          srow = a.input_row
        else
          scol = cv.left
          srow = a.input_row
        end
        @ctx.motion_set_coordinate(id, scol, srow)
        speed = @ctx.rng.uniform(@speed_range[0], @speed_range[1])
        @ctx.motion_new_path(id, "path_#{id}", speed, @ease, 0, false)
        @ctx.motion_add_waypoint(id, "path_#{id}", a.input_col, a.input_row)
        @ctx.motion_activate_path(id, "path_#{id}")
        @ctx.new_scene(id, "pour_#{id}")
        final = mapping.get(a.input_col, a.input_row)
        pg = Gradient.build([@starting, final], @final_steps, false, false)
        pairs = pg.spectrum.map { |c| [c, nil] }
        @ctx.apply_gradient(id, "pour_#{id}", [a.input_sym], @final_frames, pairs)
        @ctx.activate_scene(id, "pour_#{id}")
      end
      if gi % 2 == 0
        @pending_groups.push(group)
      else
        @pending_groups.push(group.reverse)
      end
      gi += 1
    end
    @gap = 0
    @current_group = @pending_groups.shift
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @pending_groups.empty? && @ctx.active_empty? && @current_group.empty?
      if @current_group.empty? && !@pending_groups.empty?
        @current_group = @pending_groups.shift
      end
      unless @current_group.empty?
        if @gap == 0
          k = 0
          while k < @pour_speed
            break if @current_group.empty?
            id = @current_group.shift
            @ctx.set_visible(id, true)
            @ctx.active_include(id)
            k += 1
          end
          @gap = @gap_default
        else
          @gap -= 1
        end
      end
      @ctx.update
      return @ctx.frame_string
    end
    nil
  end
end
