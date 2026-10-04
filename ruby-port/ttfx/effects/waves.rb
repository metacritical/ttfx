# Faithful waves (ttfx src/effects/waves.rs, old-engine semantics).
#
# A wave gradient travels across column/row groups (eased); each character
# plays wave_count passes of the wave symbols, then settles into its final
# gradient color. Groups are released one per tick, left to right.
class WavesEffect
  DIRECTIONS = ["column_left_to_right", "column_right_to_left",
                "row_top_to_bottom", "row_bottom_to_top",
                "center_to_outside", "outside_to_center"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @wave_symbols = o.fetch("wave_symbols", ["\u2581", "\u2582", "\u2583", "\u2584", "\u2585", "\u2586", "\u2587", "\u2588", "\u2587", "\u2586", "\u2585", "\u2584", "\u2583", "\u2582", "\u2581"])
    wave_stop_hex = o.fetch("wave_gradient_stops", ["f0ff65", "ffb102", "31a0d4", "ffb102", "f0ff65"])
    @wave_steps = o.fetch("wave_gradient_steps", [6])
    @wave_count = o.fetch("wave_count", 7)
    @wave_length = o.fetch("wave_length", 2)
    @wave_direction = o.fetch("wave_direction", "column_left_to_right")
    @wave_ease = o.fetch("wave_easing", "in_out_sine")
    stop_hex = o.fetch("final_gradient_stops", ["ffb102", "31a0d4", "f0ff65"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "diagonal")
    @wave_stops = wave_stop_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    wgrad = Gradient.build(@wave_stops, @wave_steps, false, false)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @ctx.new_scene_eased(id, "wave_#{id}", @wave_ease)
      @wave_count.times do
        pairs = wgrad.spectrum.map { |c| [c, nil] }
        @ctx.apply_gradient(id, "wave_#{id}", @wave_symbols, @wave_length, pairs)
      end
      @ctx.new_scene(id, "final_#{id}")
      fgrad = Gradient.build([wgrad.spectrum[wgrad.spectrum.length - 1], final], @final_steps, false, false)
      fgrad.spectrum.each do |c|
        @ctx.add_frame(id, "final_#{id}", a.input_sym, 10, c)
      end
      @ctx.register_event(id, "scene_complete", "wave_#{id}", "scene", "final_#{id}")
      @ctx.activate_scene(id, "wave_#{id}")
    end
    groups = cv.grouped_ids(@wave_direction)
    groups.each { |g| @pending.push(g) }
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @pending.empty? && @ctx.active_empty?
      unless @pending.empty?
        group = @pending.shift
        group.each do |id|
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
