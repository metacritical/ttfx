# Faithful middleout (ttfx src/effects/middleout.rs, old-engine semantics).
#
# Characters start at the canvas center, expand along a center line, then
# run a second "full" path home while cross-fading from white into the
# final gradient. Fully deterministic (no RNG draws).
class MiddleoutEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @starting = Color.from_hex(o.fetch("starting_color", "ffffff"))
    @direction = o.fetch("expand_direction", "vertical")
    @center_speed = o.fetch("center_movement_speed", 0.6)
    @full_speed = o.fetch("full_movement_speed", 0.6)
    @center_ease = o.fetch("center_easing", "in_out_sine")
    @full_ease = o.fetch("full_easing", "in_out_sine")
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @phase = "center"
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    cc = cv.center_column
    cr = cv.center_row
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @ctx.motion_set_coordinate(id, cc, cr)
      if @direction == "vertical"
        mid_col = a.input_col
        mid_row = cr
      else
        mid_col = cc
        mid_row = a.input_row
      end
      cpath = @ctx.motion_new_path(id, "", @center_speed, @center_ease, 0, false)
      @ctx.motion_add_waypoint(id, cpath, mid_col, mid_row)
      @ctx.motion_new_path(id, "full", @full_speed, @full_ease, 0, false)
      @ctx.motion_add_waypoint(id, "full", a.input_col, a.input_row)
      @ctx.new_scene(id, "full")
      fg = Gradient.with_steps([@starting, final], 10, false)
      pairs = fg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "full", [a.input_sym], 6, pairs)
      @ctx.motion_activate_path(id, cpath)
      @ctx.set_appearance(id, a.input_sym, @starting)
      @ctx.set_visible(id, true)
      @ctx.active_include(id)
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    if @phase == "center" && @ctx.active_empty?
      @phase = "full"
      ids = @ctx.canvas.ordered_ids.sort
      @ctx.active_clear
      ids.each { |id| @ctx.active_include(id) }
      ids.each do |id|
        @ctx.motion_activate_path(id, "full")
        @ctx.activate_scene(id, "full")
      end
    end
    unless @ctx.active_empty?
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
