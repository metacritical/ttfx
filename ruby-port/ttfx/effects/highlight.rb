# Faithful highlight (ttfx src/effects/highlight.rs, old-engine semantics).
#
# All characters start visible in their final gradient color; an easer
# sweeps a bright highlight across direction groups (added groups only).
class HighlightEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @brightness = o.fetch("highlight_brightness", 1.75)
    @direction = o.fetch("highlight_direction", "diagonal_bottom_left_to_top_right")
    @width = o.fetch("highlight_width", 8)
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @easer = nil
  end

  def build
    groups = @ctx.canvas.grouped_ids(@direction)
    @easer = SequenceEaser.new(groups, "in_out_circ", 100)
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      base = mapping.get(a.input_col, a.input_row)
      @ctx.set_appearance(id, a.input_sym, base)
      @ctx.new_scene(id, "highlight")
      bright = Color.adjust_brightness(base, @brightness)
      hg = Gradient.build([base, bright, bright, base], [3, @width, 3], false, false)
      hg.spectrum.each do |c|
        @ctx.add_frame(id, "highlight", a.input_sym, 2, c)
      end
      @ctx.set_visible(id, true)
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @ctx.active_empty? && @easer.complete?
      added, _removed = @easer.step
      added.each do |group|
        group.each do |id|
          @ctx.activate_scene(id, "highlight")
          @ctx.active_include(id)
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
