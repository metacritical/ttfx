# Faithful scattered (ttfx src/effects/scattered.rs, old-engine semantics).
#
# Characters start at random canvas positions and travel home along eased
# paths while a distance-synced gradient scene colors them; a 25-frame hold
# opens the animation.
class ScatteredEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @speed = o.fetch("movement_speed", 0.5)
    @ease = o.fetch("movement_easing", "in_out_back")
    stop_hex = o.fetch("final_gradient_stops", ["ff9048", "ab9dff", "bdffea"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @frames = o.fetch("final_gradient_frames", 9)
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @hold = 0
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      start = nil
      if cv.right < 2 || cv.top < 2
        start = [1, 1]
      else
        start = cv.random_coord(@ctx.rng, false, false)
      end
      @ctx.motion_set_coordinate(id, start[0], start[1])
      @ctx.motion_new_path(id, "path_#{id}", @speed, @ease, 0, false)
      @ctx.motion_add_waypoint(id, "path_#{id}", a.input_col, a.input_row)
      @ctx.register_event(id, "path_activated", "path_#{id}", "layer", 1)
      @ctx.register_event(id, "path_complete", "path_#{id}", "layer", 0)
      @ctx.motion_activate_path(id, "path_#{id}")
      @ctx.set_visible(id, true)
      @ctx.new_scene_synced(id, "grad_#{id}", "distance")
      cg = Gradient.with_steps([grad.spectrum[0], final], 10, false)
      pairs = cg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "grad_#{id}", [a.input_sym], @frames, pairs)
      @ctx.activate_scene(id, "grad_#{id}")
      @ctx.active_include(id)
    end
    @hold = 25
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @pending.empty? && @ctx.active_empty?
      unless @hold == 0
        @hold -= 1
        return @ctx.frame_string
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
