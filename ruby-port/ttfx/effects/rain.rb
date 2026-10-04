# Faithful rain (ttfx src/effects/rain.rs, old-engine semantics).
#
# Raindrops fall from the top of the canvas along eased paths; on arrival
# each character cross-fades from its raindrop color to its final gradient
# color. Characters are released row by row (lowest row first) with a
# random 1-2 activations per tick at random pending positions.
class RainEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    rain_hex = o.fetch("rain_colors", ["00315C", "004C8F", "0075DB", "3F91D9", "78B9F2", "9AC8F5", "B8D8F8", "E3EFFC"])
    @speed_range = o.fetch("movement_speed", [0.33, 0.57])
    rain_syms = o.fetch("rain_symbols", ["o", ".", ",", "*", "|"])
    stop_hex = o.fetch("final_gradient_stops", ["488bff", "b2e7de", "57eaf7"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "diagonal")
    @ease = o.fetch("movement_easing", "in_quart")
    @rain_colors = rain_hex.map { |h| Color.from_hex(h) }
    @rain_symbols = rain_syms
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @group_by_row = {}
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    final_map = {}
    order.each do |id|
      a = @ctx.anim(id)
      final_map[id] = mapping.get(a.input_col, a.input_row)
    end
    top = cv.top
    order.each do |id|
      a = @ctx.anim(id)
      rain_color = @ctx.rng.choice(@rain_colors)
      rain_sym = @ctx.rng.choice(@rain_symbols)
      @ctx.new_scene(id, "rain_#{id}")
      @ctx.add_frame(id, "rain_#{id}", rain_sym, 1, rain_color)
      @ctx.new_scene(id, "fade_#{id}")
      final = final_map[id]
      fg = Gradient.with_steps([rain_color, final], 7, false)
      pairs = fg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "fade_#{id}", [a.input_sym], 3, pairs)
      @ctx.activate_scene(id, "rain_#{id}")
      speed = @ctx.rng.uniform(@speed_range[0], @speed_range[1])
      @ctx.motion_set_coordinate(id, a.input_col, top)
      @ctx.motion_new_path(id, "path_#{id}", speed, @ease, 0, false)
      @ctx.motion_add_waypoint(id, "path_#{id}", a.input_col, a.input_row)
      @ctx.register_event(id, "path_complete", "path_#{id}", "scene", "fade_#{id}")
      @ctx.motion_activate_path(id, "path_#{id}")
      @pending.push(id)
    end
    by_row = {}
    @pending.each do |id|
      r = @ctx.anim(id).input_row
      list = by_row[r]
      if list.nil?
        list = []
        by_row[r] = list
      end
      list.push(id)
    end
    @group_by_row = by_row
    @pending = []
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @group_by_row.empty? && @ctx.active_empty? && @pending.empty?
      if @pending.empty? && !@group_by_row.empty?
        min_row = nil
        @group_by_row.each_key do |r|
          min_row = r if min_row.nil? || r < min_row
        end
        @pending = @group_by_row.delete(min_row)
      end
      unless @pending.empty?
        n = @ctx.rng.randint(1, 2)
        n.times do
          break if @pending.empty?
          idx = @ctx.rng.randint(0, @pending.length - 1)
          cid = @pending.delete_at(idx)
          @ctx.set_visible(cid, true)
          @ctx.active_include(cid)
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
