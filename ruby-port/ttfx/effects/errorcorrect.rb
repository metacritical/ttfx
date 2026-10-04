# Faithful errorcorrect (ttfx src/effects/errorcorrect.rs, old-engine semantics).
#
# Random pairs of characters start swapped; one pair at a time flashes an
# error scene, wipes through blocks, travels home along a synced correcting
# gradient, and settles into the final gradient.
class ErrorcorrectEffect
  BLOCK_START = ["\u2581", "\u2582", "\u2583", "\u2584", "\u2585", "\u2586", "\u2587", "\u2588"].freeze
  BLOCK_END = ["\u2587", "\u2586", "\u2585", "\u2584", "\u2583", "\u2582", "\u2581"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @error_pairs = o.fetch("error_pairs", 0.1)
    @swap_delay_default = o.fetch("swap_delay", 6)
    @error_color = Color.from_hex(o.fetch("error_color", "e74c3c"))
    @correct_color = Color.from_hex(o.fetch("correct_color", "45bf55"))
    @speed = o.fetch("movement_speed", 0.9)
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @swapped = []
    @delay = 0
    @final_map = {}
  end

  def configure_swapped(id, correcting)
    a = @ctx.anim(id)
    sym = a.input_sym
    @ctx.new_scene(id, "first_wipe")
    BLOCK_START.each do |b|
      @ctx.add_frame(id, "first_wipe", b, 3, @error_color)
    end
    @ctx.new_scene(id, "last_wipe")
    BLOCK_END.each do |b|
      @ctx.add_frame(id, "last_wipe", b, 3, @correct_color)
    end
    @ctx.new_scene(id, "initial")
    @ctx.add_frame(id, "initial", sym, 1, @error_color)
    @ctx.activate_scene(id, "initial")
    @ctx.new_scene(id, "error")
    10.times do
      @ctx.add_frame(id, "error", "\u2593", 3, @error_color)
      @ctx.add_frame(id, "error", sym, 3, [255, 255, 255])
    end
    @ctx.new_scene_synced(id, "correcting", "distance")
    pairs = correcting.spectrum.map { |c| [c, nil] }
    @ctx.apply_gradient(id, "correcting", ["\u2588"], 3, pairs)
    @ctx.new_scene(id, "final_scn")
    final = @final_map[id]
    fg = Gradient.with_steps([@correct_color, final], 10, false)
    fpairs = fg.spectrum.map { |c| [c, nil] }
    @ctx.apply_gradient(id, "final_scn", [sym], 3, fpairs)
    @ctx.register_event(id, "scene_complete", "error", "scene", "first_wipe")
    @ctx.register_event(id, "scene_complete", "first_wipe", "scene", "correcting")
    @ctx.register_event(id, "scene_complete", "first_wipe", "path", "input_coord")
    @ctx.register_event(id, "path_activated", "input_coord", "layer", 1)
    @ctx.register_event(id, "path_complete", "input_coord", "layer", 0)
    @ctx.register_event(id, "path_complete", "input_coord", "scene", "last_wipe")
    @ctx.register_event(id, "scene_complete", "last_wipe", "scene", "final_scn")
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      @final_map[id] = mapping.get(a.input_col, a.input_row)
    end
    order.each do |id|
      a = @ctx.anim(id)
      @ctx.new_scene(id, "spawn")
      @ctx.add_frame(id, "spawn", a.input_sym, 1, @final_map[id])
      @ctx.activate_scene(id, "spawn")
      @ctx.set_visible(id, true)
    end
    pool = cv.ordered_ids.dup
    correcting = Gradient.with_steps([@error_color, @correct_color], 10, false)
    count = (@error_pairs * order.length.to_f).to_i
    count.times do
      break if pool.length < 2
      i1 = @ctx.rng.randrange(0, pool.length)
      c1 = pool.delete_at(i1)
      i2 = @ctx.rng.randrange(0, pool.length)
      c2 = pool.delete_at(i2)
      a1 = @ctx.anim(c1)
      a2 = @ctx.anim(c2)
      c1c = [a1.input_col, a1.input_row]
      c2c = [a2.input_col, a2.input_row]
      @ctx.motion_set_coordinate(c1, c2c[0], c2c[1])
      @ctx.motion_new_path(c1, "input_coord", @speed, nil, 0, false)
      @ctx.motion_add_waypoint(c1, "input_coord", c1c[0], c1c[1])
      @ctx.motion_set_coordinate(c2, c1c[0], c1c[1])
      @ctx.motion_new_path(c2, "input_coord", @speed, nil, 0, false)
      @ctx.motion_add_waypoint(c2, "input_coord", c2c[0], c2c[1])
      @swapped.push([c1, c2])
      configure_swapped(c1, correcting)
      configure_swapped(c2, correcting)
    end
    @delay = 0
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    if !@swapped.empty? && @delay == 0
      pair = @swapped.shift
      pair.each do |id|
        @ctx.activate_scene(id, "error")
        @ctx.active_include(id)
      end
      @delay = @swap_delay_default
    elsif @delay != 0
      @delay -= 1
    end
    unless @ctx.active_empty?
      @ctx.update
      return @ctx.frame_string
    end
    nil
  end
end
