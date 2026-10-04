# Faithful spray (ttfx src/effects/spray.rs, old-engine semantics).
#
# Characters spray out from an origin point along eased paths, each
# cross-fading from a random spectrum color to its final color. A volume
# fraction of the shuffled pending list is released per tick.
class SprayEffect
  POSITIONS = ["n", "ne", "e", "se", "s", "sw", "w", "nw", "center"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @position = o.fetch("spray_position", "e")
    @volume_ratio = o.fetch("spray_volume", 0.005)
    @speed_range = o.fetch("movement_speed_range", [0.6, 1.4])
    @ease = o.fetch("movement_easing", "out_expo")
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @volume = 1
  end

  def spray_origin(cv)
    case @position
    when "center"
      [cv.center_column, cv.center_row]
    when "n"
      [cv.right / 2, cv.top]
    when "nw"
      [cv.left, cv.top]
    when "w"
      [cv.left, cv.top / 2]
    when "sw"
      [cv.left, cv.bottom]
    when "s"
      [cv.right / 2, cv.bottom]
    when "se"
      [cv.right - 1, cv.bottom]
    when "e"
      [cv.right - 1, cv.top / 2]
    when "ne"
      [cv.right - 1, cv.top]
    end
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
    origin = spray_origin(cv)
    order.each do |id|
      a = @ctx.anim(id)
      speed = @ctx.rng.uniform(@speed_range[0], @speed_range[1])
      @ctx.motion_set_coordinate(id, origin[0], origin[1])
      @ctx.motion_new_path(id, "path_#{id}", speed, @ease, 0, false)
      @ctx.motion_add_waypoint(id, "path_#{id}", a.input_col, a.input_row)
      @ctx.register_event(id, "path_activated", "path_#{id}", "layer", 1)
      @ctx.register_event(id, "path_complete", "path_#{id}", "layer", 0)
      @ctx.new_scene(id, "drop_#{id}")
      final = final_map[id]
      start_color = @ctx.rng.choice(grad.spectrum)
      sg = Gradient.with_steps([start_color, final], 7, false)
      pairs = sg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "drop_#{id}", [a.input_sym], 20, pairs)
      @ctx.activate_scene(id, "drop_#{id}")
      @ctx.motion_activate_path(id, "path_#{id}")
      @pending.push(id)
    end
    @ctx.rng.shuffle(@pending)
    @volume = (@pending.length.to_f * @volume_ratio).to_i
    @volume = 1 if @volume < 1
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @pending.empty? && @ctx.active_empty?
      unless @pending.empty?
        n = @ctx.rng.randint(1, @volume)
        n.times do
          break if @pending.empty?
          id = @pending.pop
          @ctx.set_visible(id, true)
          @ctx.active_include(id)
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
