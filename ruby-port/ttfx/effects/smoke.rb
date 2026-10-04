# Faithful smoke (ttfx src/effects/smoke.rs, old-engine semantics).
#
# A weighted Prim's spanning tree is grown over the canvas, then a
# breadth-first flood fills it: smoke symbols wash over characters, each
# settling from smoke gray into its final gradient color.
class SmokeEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @starting = Color.from_hex(o.fetch("starting_color", "7A7A7A"))
    @smoke_symbols = o.fetch("smoke_symbols", ["\u2591", "\u2592", "\u2593", "\u2592", "\u2591"])
    smoke_hex = o.fetch("smoke_gradient_stops", ["242424", "FFFFFF"])
    @whole_canvas = o.fetch("use_whole_canvas", false)
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @smoke_stops = smoke_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @fill_alg = nil
  end

  def build
    limit = !@whole_canvas
    gen = PrimsWeighted.new(@ctx, nil, limit)
    coord = @ctx.canvas.random_coord(@ctx.rng, false, limit)
    found = @ctx.canvas.char_by_coord(coord[0], coord[1])
    @fill_alg = BreadthFirst.new(@ctx, found, limit)
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    black = [0, 0, 0]
    sgrad = Gradient.build(@smoke_stops + @final_stops.reverse, [3, 4], false, false)
    all = cv.all_ids
    order = cv.ordered_ids(all)
    order.each do |id|
      a = @ctx.anim(id)
      @ctx.set_visible(id, true)
      final = mapping.get(a.input_col, a.input_row) || black
      @ctx.new_scene(id, "paint_#{id}")
      pg = Gradient.with_steps(@final_stops + [final], 5, false)
      pairs = pg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "paint_#{id}", [a.input_sym], 5, pairs)
      @ctx.new_scene(id, "smoke_#{id}")
      spairs = sgrad.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "smoke_#{id}", @smoke_symbols, 3, spairs)
      @ctx.register_event(id, "scene_complete", "smoke_#{id}", "scene", "paint_#{id}")
      @ctx.set_appearance(id, a.input_sym, @starting)
    end
    until gen.complete
      gen.step(@ctx)
    end
    start = @fill_alg.starting_char
    @ctx.activate_scene(start, "smoke_#{start}")
    @ctx.active_include(start)
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    fill = @fill_alg
    if !fill.complete || !@ctx.active_empty?
      unless fill.complete
        fill.step(@ctx)
        fill.explored_last_step.each do |id|
          @ctx.activate_scene(id, "smoke_#{id}")
          @ctx.active_include(id)
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
