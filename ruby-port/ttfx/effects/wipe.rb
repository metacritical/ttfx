# Faithful wipe (ttfx src/effects/wipe.rs, old-engine semantics).
#
# Every character gets one "wipe" scene: its final gradient color reached
# from the gradient's first color. A SequenceEaser over the wipe direction's
# groups reveals characters (and hides + rewinds them when the easing runs
# backward). No RNG is drawn.
class WipeEffect
  GROUPS = ["column_left_to_right", "column_right_to_left",
            "row_top_to_bottom", "row_bottom_to_top",
            "diagonal_bottom_left_to_top_right",
            "diagonal_top_right_to_bottom_left",
            "diagonal_top_left_to_bottom_right",
            "diagonal_bottom_right_to_top_left",
            "center_to_outside", "outside_to_center"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @direction = o.fetch("wipe_direction", "diagonal_top_left_to_bottom_right")
    @delay_default = o.fetch("wipe_delay", 0)
    @ease = o.fetch("wipe_ease", "in_out_circ")
    stop_hex = o.fetch("final_gradient_stops", ["833ab4", "fd1d1d", "fcb045"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @frames = o.fetch("final_gradient_frames", 3)
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @wipe_delay = @delay_default
    @easer = nil
  end

  def build
    groups = @ctx.canvas.grouped_ids(@direction)
    @easer = SequenceEaser.new(groups, @ease, 100)
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    first = grad.spectrum[0]
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @ctx.new_scene(id, "wipe")
      # Dynamic path would use input colors; plain input has none, so the
      # frames carry no colors (matches the old engine's dynamic output).
      dynamic = false
      if dynamic
        count = 1
        @final_steps.each { |s| count += s }
        count.times do
          @ctx.add_frame(id, "wipe", a.input_sym, @frames, nil)
        end
      else
        wg = Gradient.build([first, final], @final_steps, false, false)
        pairs = wg.spectrum.map { |c| [c, nil] }
        @ctx.apply_gradient(id, "wipe", [a.input_sym], @frames, pairs)
      end
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    return nil if @easer.complete? && @ctx.active_empty?
    if @wipe_delay == 0
      added, removed = @easer.step
      added.each do |group|
        group.each do |id|
          @ctx.activate_scene(id, "wipe")
          @ctx.set_visible(id, true)
          @ctx.active_include(id)
        end
      end
      removed.each do |group|
        group.each do |id|
          @ctx.deactivate_scene(id)
          @ctx.reset_scene(id, "wipe")
          @ctx.set_visible(id, false)
        end
      end
      @wipe_delay = @delay_default
    else
      @wipe_delay -= 1
    end
    @ctx.update(self)
    @ctx.frame_string
  end
end
