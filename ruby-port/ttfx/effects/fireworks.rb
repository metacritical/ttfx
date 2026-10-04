# Faithful fireworks (ttfx src/effects/fireworks.rs, old-engine semantics).
#
# Shells launch from the bottom, arc to an apex, explode outward along
# bezier bloom paths, then fall home. Looping launch scenes, step-synced
# bloom scenes, per-shell colors. Fully deterministic (seeded RNG only).
class FireworksEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @explode_anywhere = o.fetch("explode_anywhere", false)
    fire_hex = o.fetch("firework_colors", ["88F7E2", "44D492", "F5EB67", "FFA15C", "FA233E"])
    @firework_symbol = o.fetch("firework_symbol", "o")
    @volume_ratio = o.fetch("firework_volume", 0.05)
    @launch_delay_default = o.fetch("launch_delay", 45)
    @explode_ratio = o.fetch("explode_distance", 0.2)
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "horizontal")
    @firework_colors = fire_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @shells = []
    @volume = 0
    @explode_distance = 0
    @final_map = {}
    @launch_delay = 0
  end

  def build
    cv = @ctx.canvas
    @volume = PyCompat.round_half_even(@volume_ratio * cv.char_count.to_f)
    @volume = 1 if @volume < 1
    @explode_distance = PyCompat.round_half_even(cv.right.to_f * @explode_ratio)
    @explode_distance = 15 if @explode_distance > 15
    @explode_distance = 1 if @explode_distance < 1
    @launch_delay = 0
    prepare_waypoints
    prepare_scenes
  end

  def prepare_waypoints
    cv = @ctx.canvas
    order = cv.ordered_ids
    shell = []
    origin_x = 0
    origin = [0, 0]
    circle = []
    order.each do |id|
      if shell.length == @volume || shell.empty?
        origin_x = @ctx.rng.randrange(0, cv.right)
        @shells.push(shell)
        shell = []
        a = @ctx.anim(id)
        min_row = @explode_anywhere ? cv.bottom : a.input_row
        origin = [origin_x, @ctx.rng.randrange(min_row, cv.top + 1)]
        circle = Geometry.coords_in_circle(origin[0], origin[1], @explode_distance)
      end
      a = @ctx.anim(id)
      @ctx.motion_set_coordinate(id, origin_x, cv.bottom)
      @ctx.motion_new_path(id, "apex_pth", 0.35, "out_expo", 0, false, 2)
      @ctx.motion_add_waypoint(id, "apex_pth", origin[0], origin[1])
      speed = @ctx.rng.uniform(0.2, 0.4)
      @ctx.motion_new_path(id, "explode_pth", speed, "out_circ", 0, false, 2)
      ex = @ctx.rng.choice(circle)
      @ctx.motion_add_waypoint(id, "explode_pth", ex[0], ex[1])
      bx, by = Geometry.extrapolate_ray(origin[0], origin[1], ex[0], ex[1], (@explode_distance / 2).to_f)
      wy = by - 7
      wy = 1 if wy < 1
      @ctx.motion_add_waypoint(id, "explode_pth", bx, wy, [[bx, by]])
      @ctx.motion_new_path(id, "input_pth", 0.6, "in_out_quart", 0, false, 2)
      @ctx.motion_add_waypoint(id, "input_pth", a.input_col, a.input_row, [[bx, 1]])
      @ctx.register_event(id, "path_complete", "apex_pth", "path", "explode_pth")
      @ctx.register_event(id, "path_complete", "explode_pth", "path", "input_pth")
      @ctx.register_event(id, "path_complete", "input_pth", "layer", 0)
      @ctx.motion_activate_path(id, "apex_pth")
      shell.push(id)
    end
    @shells.push(shell) unless shell.empty?
  end

  def prepare_scenes
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    white = [255, 255, 255]
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      @final_map[id] = mapping.get(a.input_col, a.input_row)
    end
    @shells.each do |shell|
      shell_color = @ctx.rng.choice(@firework_colors)
      sg = Gradient.with_steps([shell_color, white, shell_color], 5, false)
      shell.each do |id|
        a = @ctx.anim(id)
        @ctx.new_scene_loop(id, "launch")
        @ctx.add_frame(id, "launch", @firework_symbol, 2, shell_color)
        @ctx.add_frame(id, "launch", @firework_symbol, 1, white)
        @ctx.new_scene_synced(id, "bloom", "step")
        sg.spectrum.each do |c|
          @ctx.add_frame(id, "bloom", a.input_sym, 2, c)
        end
        @ctx.new_scene(id, "fall_scn")
        final = @final_map[id]
        fg = Gradient.with_steps([shell_color, final], 15, false)
        pairs = fg.spectrum.map { |c| [c, nil] }
        @ctx.apply_gradient(id, "fall_scn", [a.input_sym], 10, pairs)
        @ctx.activate_scene(id, "launch")
        @ctx.register_event(id, "path_complete", "apex_pth", "scene", "bloom")
        @ctx.register_event(id, "path_activated", "input_pth", "scene", "fall_scn")
      end
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @shells.empty? && @ctx.active_empty?
      if !@shells.empty? && @launch_delay <= 0
        group = @shells.pop
        group.each do |id|
          @ctx.set_visible(id, true)
          @ctx.active_include(id)
        end
        @launch_delay = (@launch_delay_default.to_f * @ctx.rng.uniform(0.5, 1.5)).to_i
      end
      @launch_delay -= 1
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
