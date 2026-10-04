# Faithful spotlights (ttfx src/effects/spotlights.rs, old-engine semantics).
#
# Invisible spotlight movers sweep bezier-chained search paths while input
# characters illuminate by proximity with beam falloff; the spotlights then
# converge on the canvas center and the beam expands to full coverage.
class SpotlightsEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @width_ratio = o.fetch("beam_width_ratio", 2.0)
    @falloff = o.fetch("beam_falloff", 0.3)
    @search_default = o.fetch("search_duration", 550)
    @speed_range = o.fetch("search_speed_range", [0.35, 0.75])
    @count = o.fetch("spotlight_count", 3)
    stop_hex = o.fetch("final_gradient_stops", ["ab48ff", "e7b2b2", "fffebd"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @illuminated = []
    @scratch = []
    @color_map = {}
    @spotlights = []
    @range = 1
    @search_left = 0
    @searching = true
    @expanding = false
    @complete = false
  end

  def plain_length(c1col, c1row, c2col, c2row)
    dx = (c2col - c1col).to_f
    dy = (c2row - c1row).to_f
    Math.sqrt(dx * dx + dy * dy)
  end

  def min_distance_coord(origin_col, origin_row, minimum)
    loop do
      c = @ctx.canvas.random_coord(@ctx.rng, false, false)
      d = plain_length(origin_col, origin_row, c[0], c[1])
      return c if d >= minimum.to_f
    end
  end

  def make_spotlights(n)
    out = []
    min_dist = @ctx.canvas.floor_div(@ctx.canvas.right, 4)
    n.times do
      spawn = @ctx.canvas.random_coord(@ctx.rng, true, false)
      id = @ctx.add_character("O", spawn[0], spawn[1])
      out.push(id)
      targets = []
      last = @ctx.canvas.random_coord(@ctx.rng, false, false)
      targets.push(last)
      10.times do
        last = min_distance_coord(last[0], last[1], min_dist)
        targets.push(last)
      end
      names = []
      targets.each do |t|
        speed = @ctx.rng.uniform(@speed_range[0], @speed_range[1])
        pname = names.length.to_s
        @ctx.motion_new_path(id, pname, speed, "in_out_quad", 0, false)
        bc = @ctx.canvas.random_coord(@ctx.rng, true, false)
        @ctx.motion_add_waypoint(id, pname, t[0], t[1], [[bc[0], bc[1]]])
        names.push(pname)
      end
      @ctx.chain_paths(id, names, true)
      @ctx.motion_new_path(id, "center", 0.5, "in_out_sine", 0, false)
      @ctx.motion_add_waypoint(id, "center", @ctx.canvas.center_column, @ctx.canvas.center_row)
    end
    out
  end

  def spotlightable?(id)
    @ctx.anim(id).input_sym != " "
  end

  def illuminate(range)
    cv = @ctx.canvas
    in_range = []
    @spotlights.each do |sid|
      a = @ctx.anim(sid)
      Geometry.coords_in_circle(a.cur_col, a.cur_row, range).each do |cc|
        id = cv.char_by_coord(cc[0], cc[1])
        next if id.nil?
        if spotlightable?(id) && !in_range.include?(id)
          in_range.push(id)
        end
      end
    end
    @illuminated.sort.each do |id|
      next if in_range.include?(id)
      a = @ctx.anim(id)
      @ctx.set_appearance(id, a.input_sym, @color_map[id][1])
    end
    in_range.sort.each do |id|
      a = @ctx.anim(id)
      best = nil
      @spotlights.each do |sid|
        s = @ctx.anim(sid)
        d = @ctx.line_length(s.cur_col, s.cur_row, a.input_col, a.input_row)
        best = d if best.nil? || d < best
      end
      color = @color_map[id][0]
      edge = range.to_f * (1.0 - @falloff)
      if best > edge
        factor = 1.0 - (best - edge) / (range.to_f * @falloff)
        factor = 0.2 if factor < 0.2
        color = Color.adjust_brightness(@color_map[id][0], factor)
      end
      @ctx.set_appearance(id, a.input_sym, color)
    end
    @scratch = @illuminated
    @illuminated = in_range
  end

  def build
    @spotlights = make_spotlights(@count)
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      bright = mapping.get(a.input_col, a.input_row)
      dark = Color.adjust_brightness(bright, 0.2)
      @ctx.set_visible(id, true)
      @color_map[id] = [bright, dark]
      @ctx.set_appearance(id, a.input_sym, dark)
    end
    smallest = cv.right < cv.top ? cv.right : cv.top
    @range = (smallest.to_f / @width_ratio).floor
    @range = smallest if @range > smallest
    @range = 1 if @range < 1
    @search_left = @search_default
    @searching = true
    @expanding = false
    @complete = false
    @spotlights.each do |sid|
      @ctx.motion_activate_path(sid, "0")
      @ctx.active_include(sid)
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @complete
      illuminate(@range)
      if @searching
        @search_left -= 1
        if @search_left == 0
          @spotlights.each do |sid|
            @ctx.motion_activate_path(sid, "center")
          end
          @searching = false
        end
      end
      any_active = false
      @spotlights.each do |sid|
        unless @ctx.anim(sid).active_path.nil?
          any_active = true
          break
        end
      end
      unless any_active
        while @spotlights.length > 1
          @spotlights.pop
        end
        @expanding = true
        @range += 1
        cv = @ctx.canvas
        biggest = cv.right > cv.top ? cv.right : cv.top
        limit = (biggest.to_f / 1.5).floor
        @complete = true if @range.to_f > limit
      end
      @ctx.update
      return @ctx.frame_string
    end
    nil
  end
end
