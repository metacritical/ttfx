# Faithful colorshift (ttfx src/effects/colorshift.rs, old-engine semantics).
#
# A looping gradient washes over the text (optionally traveling across the
# canvas); a per-character callback replays it `cycles` times, then settles
# each character into its final gradient color. Fully deterministic.
class ColorshiftEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    stop_hex = o.fetch("gradient_stops", ["e81416", "ffa500", "faeb36", "79c314", "487de7", "4b369d", "70369d"])
    @gradient_steps = o.fetch("gradient_steps", [12])
    @gradient_frames = o.fetch("gradient_frames", 2)
    @no_travel = o.fetch("no_travel", false)
    @travel_direction = o.fetch("travel_direction", "radial")
    @reverse_travel = o.fetch("reverse_travel_direction", false)
    @no_loop = o.fetch("no_loop", false)
    @cycles = o.fetch("cycles", 3)
    @skip_final = o.fetch("skip_final_gradient", false)
    final_hex = o.fetch("final_gradient_stops", ["e81416", "ffa500", "faeb36", "79c314", "487de7", "4b369d", "70369d"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @stops = stop_hex.map { |h| Color.from_hex(h) }
    @final_stops = final_hex.map { |h| Color.from_hex(h) }
    @final_map = {}
    @loop_count = {}
  end

  def on_callback(ctx, id, _cbid)
    n = @loop_count[id] || 0
    n += 1
    @loop_count[id] = n
    if @cycles == 0 || n < @cycles
      ctx.activate_scene(id, "gradient")
    elsif !@skip_final
      ctx.activate_scene(id, "final_gradient")
    end
  end

  def rotated_spectrum(grad, col, row)
    spec = grad.spectrum
    return spec if @no_travel
    cv = @ctx.canvas
    idx = 0.0
    case @travel_direction
    when "horizontal"
      idx = col.to_f / cv.right.to_f
    when "vertical"
      idx = row.to_f / cv.top.to_f
    when "diagonal"
      idx = (row + col).to_f / (cv.right + cv.top).to_f
    when "radial"
      idx = Gradient.radial_fraction(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, col, row)
    end
    shift = (spec.length.to_f * idx).to_i
    shift = -shift if @reverse_travel
    len = spec.length
    k = 0
    if shift < 0
      k = len + shift
      k = 0 if k < 0
    else
      k = shift
      k = len if k > len
    end
    spec[k, spec.length] + spec[0, k]
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
    loop_flag = !@no_loop
    wave = Gradient.build(@stops, @gradient_steps, false, loop_flag)
    order.each do |id|
      a = @ctx.anim(id)
      @ctx.set_visible(id, true)
      colors = rotated_spectrum(wave, a.input_col, a.input_row)
      @ctx.new_scene(id, "gradient")
      colors.each do |c|
        @ctx.add_frame(id, "gradient", a.input_sym, @gradient_frames, c)
      end
      @ctx.new_scene(id, "final_gradient")
      final = @final_map[id]
      fg = Gradient.with_steps([colors[colors.length - 1], final], 8, false)
      pairs = fg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "final_gradient", [a.input_sym], @gradient_frames, pairs)
      @ctx.activate_scene(id, "gradient")
      @ctx.active_include(id)
      @ctx.register_event(id, "scene_complete", "gradient", "callback", nil)
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
