# Faithful randomsequence (ttfx src/effects/random_sequence.rs).
#
# Each character fades from the terminal background into its final color;
# characters are released in shuffled order, a fixed number per tick.
class RandomsequenceEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @speed = o.fetch("speed", 0.007)
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @frames = o.fetch("final_gradient_frames", 8)
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @per_tick = 1
  end

  def build
    cv = @ctx.canvas
    @per_tick = (@speed * cv.char_count).to_i
    @per_tick = 1 if @per_tick < 1
    bg = [0, 0, 0]
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @ctx.set_visible(id, false)
      @ctx.new_scene(id, "randomsequence_#{id}")
      fg = Gradient.with_steps([bg, final], 7, false)
      pairs = fg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "randomsequence_#{id}", [a.input_sym], @frames, pairs)
      @ctx.activate_scene(id, "randomsequence_#{id}")
      @pending.push(id)
    end
    @ctx.rng.shuffle(@pending)
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @pending.empty? && @ctx.active_empty?
      k = 0
      while k < @per_tick
        break if @pending.empty?
        id = @pending.pop
        @ctx.set_visible(id, true)
        @ctx.active_include(id)
        k += 1
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
