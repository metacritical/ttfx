# Faithful sweep (ttfx src/effects/sweep.rs, old-engine semantics).
#
# A first easer sweep reveals characters uncolored (gray shimmer into gray);
# the easer then re-runs over the second direction coloring them into the
# final gradient. Operates over input + fill characters.
class SweepEffect
  GRAYS = ["A0A0A0", "808080", "404040", "202020", "101010"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @symbols = o.fetch("sweep_symbols", ["\u2588", "\u2593", "\u2592", "\u2591"])
    @first_direction = o.fetch("first_sweep_direction", "column_right_to_left")
    @second_direction = o.fetch("second_sweep_direction", "column_left_to_right")
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "ffffff"])
    @final_steps = o.fetch("final_gradient_steps", [8])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @complete = false
    @first_phase = true
    @easer = nil
    @second_groups = []
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    grays = GRAYS.map { |h| Color.from_hex(h) }
    gray80 = [128, 128, 128]
    black = [0, 0, 0]
    all = cv.all_ids
    order = cv.ordered_ids(all)
    final_map = {}
    order.each do |id|
      a = @ctx.anim(id)
      unless a.is_fill
        final_map[id] = mapping.get(a.input_col, a.input_row)
      end
      @ctx.new_scene(id, "initial_sweep")
      @symbols.each do |sym|
        @ctx.add_frame(id, "initial_sweep", sym, 5, @ctx.rng.choice(grays))
      end
      @ctx.add_frame(id, "initial_sweep", a.input_sym, 1, gray80)
      @ctx.new_scene(id, "second_sweep")
      @symbols.each do |sym|
        @ctx.add_frame(id, "second_sweep", sym, 5, @ctx.rng.choice(grad.spectrum))
      end
      if a.is_fill
        fcol = black
      else
        fcol = final_map[id]
      end
      @ctx.add_frame(id, "second_sweep", a.input_sym, 1, fcol)
    end
    first_groups = cv.grouped_ids(@first_direction, all)
    @easer = SequenceEaser.new(first_groups, "in_out_circ", 100)
    @second_groups = cv.grouped_ids(@second_direction, all)
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @ctx.active_empty? && @complete
      added, _removed = @easer.step
      added.each do |group|
        group.each do |id|
          if @first_phase
            @ctx.set_visible(id, true)
          end
          if @first_phase
            @ctx.activate_scene(id, "initial_sweep")
          else
            @ctx.activate_scene(id, "second_sweep")
          end
        end
        group.each do |id|
          @ctx.active_include(id)
        end
      end
      if @easer.complete? && @first_phase
        @easer.resequence(@second_groups)
        @first_phase = false
      elsif @easer.complete? && !@first_phase
        @complete = true
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
