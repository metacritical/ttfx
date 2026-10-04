# Faithful expand (ttfx src/effects/expand.rs, old-engine semantics).
#
# Characters start at the canvas center and travel home along eased paths
# while a distance-synced gradient scene colors them. Fully deterministic
# (no RNG draws).
class ExpandEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @ease = o.fetch("expand_easing", "in_out_quart")
    @speed = o.fetch("movement_speed", 0.35)
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    first = grad.spectrum[0]
    center_col = cv.center_column
    center_row = cv.center_row
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @ctx.motion_set_coordinate(id, center_col, center_row)
      @ctx.motion_new_path(id, "path_#{id}", @speed, @ease, 0, false)
      @ctx.motion_add_waypoint(id, "path_#{id}", a.input_col, a.input_row)
      @ctx.register_event(id, "path_activated", "path_#{id}", "layer", 1)
      @ctx.register_event(id, "path_complete", "path_#{id}", "layer", 0)
      @ctx.motion_activate_path(id, "path_#{id}")
      @ctx.set_visible(id, true)
      @ctx.active_include(id)
      @ctx.new_scene_synced(id, "grad_#{id}", "distance")
      cg = Gradient.with_steps([first, final], 10, false)
      pairs = cg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "grad_#{id}", [a.input_sym], 5, pairs)
      @ctx.activate_scene(id, "grad_#{id}")
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @ctx.active_empty?
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
