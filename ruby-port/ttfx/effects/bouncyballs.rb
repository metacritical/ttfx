# Faithful bouncyballs (ttfx src/effects/bouncyballs.rs, old-engine semantics).
#
# Ball symbols drop from above the canvas along bouncy eased paths; on
# landing each character cross-fades from its ball color to its final
# gradient color. Released row by row with 2-6 random activations per drop.
class BouncyballsEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    ball_hex = o.fetch("ball_colors", ["d1f4a5", "96e2a4", "5acda9"])
    @ball_symbols = o.fetch("ball_symbols", ["*", "o", "O", "0", "."])
    @delay_default = o.fetch("ball_delay", 4)
    @speed = o.fetch("movement_speed", 0.45)
    @ease = o.fetch("movement_easing", "out_bounce")
    stop_hex = o.fetch("final_gradient_stops", ["f8ffae", "43c6ac"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "diagonal")
    @ball_colors = ball_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @group_by_row = {}
    @delay = 0
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    top = cv.top
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      color = @ctx.rng.choice(@ball_colors)
      sym = @ctx.rng.choice(@ball_symbols)
      @ctx.new_scene(id, "ball_#{id}")
      @ctx.add_frame(id, "ball_#{id}", sym, 1, color)
      @ctx.new_scene(id, "final_#{id}")
      fg = Gradient.with_steps([color, final], 10, false)
      pairs = fg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "final_#{id}", [a.input_sym], 6, pairs)
      drop_row = (top.to_f * @ctx.rng.uniform(1.0, 1.5)).to_i
      @ctx.motion_set_coordinate(id, a.input_col, drop_row)
      @ctx.motion_new_path(id, "path_#{id}", @speed, @ease, 0, false)
      @ctx.motion_add_waypoint(id, "path_#{id}", a.input_col, a.input_row)
      @ctx.motion_activate_path(id, "path_#{id}")
      @ctx.activate_scene(id, "ball_#{id}")
      @ctx.register_event(id, "path_complete", "path_#{id}", "scene", "final_#{id}")
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
    @delay = 0
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
        if @delay == 0
          n = @ctx.rng.randint(2, 6)
          n.times do
            break if @pending.empty?
            idx = @ctx.rng.randint(0, @pending.length - 1)
            cid = @pending.delete_at(idx)
            @ctx.set_visible(cid, true)
            @ctx.active_include(cid)
          end
          @delay = @delay_default
        else
          @delay -= 1
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
