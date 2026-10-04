# Rings effect ported from src/fx/effects/rings.rs.
# Disperse characters, rotate around alternating rings, then return home.
class RingsEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @ring_colors = o.fetch("ring_colors", ["ab48ff", "e7b2b2", "fffebd"]).map { |h| Color.from_hex(h) }
    @ring_gap_ratio = o.fetch("ring_gap", 0.1)
    @spin_duration = o.fetch("spin_duration", 200)
    @spin_speed = o.fetch("spin_speed", [0.25, 1.0])
    @disperse_duration = o.fetch("disperse_duration", 200)
    @cycles = o.fetch("spin_disperse_cycles", 3)
    @stops = o.fetch("final_gradient_stops", ["ab48ff", "e7b2b2", "fffebd"]).map { |h| Color.from_hex(h) }
    @steps = o.fetch("final_gradient_steps", [12])
    @direction = o.fetch("final_gradient_direction", "vertical")
    @rings = []
    @non_ring = []
  end

  def build
    cv = @ctx.canvas
    @ring_gap = [PyCompat.round_half_even([cv.top, cv.right].min * @ring_gap_ratio), 1].max
    gradient = Gradient.build(@stops, @steps, false, false)
    mapping = gradient.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @direction)
    ids = cv.ordered_ids
    ids.each do |id|
      a = @ctx.anim(id)
      @ctx.new_scene(id, "home")
      @ctx.add_frame(id, "home", a.input_sym, 1, mapping.get(a.input_col, a.input_row))
      @ctx.motion_new_path(id, "home", 0.8, "out_quad", 0, false)
      @ctx.motion_add_waypoint(id, "home", a.input_col, a.input_row)
      @ctx.activate_scene(id, "home")
      @ctx.set_visible(id, true)
    end
    pending = @ctx.rng.shuffle(ids.dup)
    radius = 1
    ring_index = 0
    while radius < [cv.right, cv.top].max
      coords = cv.find_coords_on_circle(cv.center_column, cv.center_row, radius, 7 * radius, true)
      inside = coords.count { |c, r| c >= cv.left && c <= cv.right && r >= cv.bottom && r <= cv.top }
      break if coords.empty? || inside.to_f / coords.length < 0.25
      color = @ring_colors[ring_index % @ring_colors.length]
      speed = @ctx.rng.uniform(@spin_speed[0], @spin_speed[1])
      chars = []
      coords.length.times do |idx|
        id = pending.shift
        break if id.nil?
        a = @ctx.anim(id)
        ordered = ring_index.odd? ? coords.reverse : coords
        rotated = ordered[idx..-1] + ordered[0...idx]
        final = mapping.get(a.input_col, a.input_row)
        @ctx.new_scene(id, "ring")
        Gradient.with_steps([final, color], 8, false).spectrum.each { |fg| @ctx.add_frame(id, "ring", a.input_sym, 3, fg) }
        @ctx.new_scene(id, "disperse")
        Gradient.with_steps([color, final], 8, false).spectrum.each { |fg| @ctx.add_frame(id, "disperse", a.input_sym, 10, fg) }
        paths = []
        rotated.each_with_index do |(col, row), k|
          path = "orbit_#{ring_index}_#{k}"
          @ctx.motion_new_path(id, path, speed, nil, 0, false)
          @ctx.motion_add_waypoint(id, path, col, row)
          paths << path
        end
        @ctx.chain_paths(id, paths, true)
        chars << { id: id, coords: rotated, paths: paths, cur: 0, last: 0 }
      end
      @rings << chars unless chars.empty?
      ring_index += 1
      radius += @ring_gap
    end
    pending.each do |id|
      col, row = cv.random_coord(@ctx.rng, true, false)
      @ctx.motion_new_path(id, "external", 0.8, "out_sine", 0, false)
      @ctx.motion_add_waypoint(id, "external", col, row)
      @ctx.register_event(id, "path_complete", "external", "callback", 0)
      @non_ring << id
    end
    @phase = "start"
    @start_left = 100
    @disperse_left = @disperse_duration
    @spin_left = @spin_duration
    @cycles_left = @cycles
    @initial_disperse = false
  end

  def on_callback(ctx, id, callback_id)
    ctx.set_visible(id, false) if callback_id == 0
  end

  def set_disperse_path(ch, origin_col, origin_row)
    side = @ring_gap * 2 + 1
    points = []
    5.times do
      index = @ctx.rng.randrange(0, side * side)
      points << [origin_col - @ring_gap + index / side, origin_row - @ring_gap + index % side]
    end
    id = ch[:id]
    @ctx.motion_new_path(id, "scatter", 0.14, nil, 0, true)
    points.each { |col, row| @ctx.motion_add_waypoint(id, "scatter", col, row) }
    points[0]
  end

  def next_frame
    return nil if @phase == "complete"
    case @phase
    when "start"
      if @start_left == 0
        @phase = "disperse"
      else
        @start_left -= 1
      end
    when "disperse"
      if !@initial_disperse
        @initial_disperse = true
        @rings.flatten.each do |ch|
          id = ch[:id]
          target = set_disperse_path(ch, *ch[:coords][0])
          @ctx.motion_new_path(id, "initial", 0.3, "out_cubic", 0, false)
          @ctx.motion_add_waypoint(id, "initial", target[0], target[1])
          @ctx.register_event(id, "path_complete", "initial", "path", "scatter")
          @ctx.activate_scene(id, "disperse")
          @ctx.motion_activate_path(id, "initial")
          @ctx.active_include(id)
        end
        @non_ring.each { |id| @ctx.motion_activate_path(id, "external"); @ctx.active_include(id) }
      elsif @disperse_left == 0
        @phase = "spin"
        @cycles_left -= 1
        @spin_left = @spin_duration
        @rings.flatten.each do |ch|
          id = ch[:id]
          target = ch[:coords][ch[:last]]
          path = ch[:paths][ch[:last]]
          @ctx.motion_new_path(id, "condense", 0.1, nil, 0, false)
          @ctx.motion_add_waypoint(id, "condense", target[0], target[1])
          @ctx.register_event(id, "path_complete", "condense", "path", path)
          @ctx.motion_activate_path(id, "condense")
          @ctx.activate_scene(id, "ring")
        end
      else
        @disperse_left -= 1
      end
    when "spin"
      if @spin_left == 0
        if @cycles_left == 0
          @phase = "final"
          @ctx.canvas.ordered_ids.each do |id|
            @ctx.set_visible(id, true)
            @ctx.motion_activate_path(id, "home")
            @ctx.active_include(id)
            @ctx.activate_scene(id, "disperse") unless @non_ring.include?(id)
          end
        else
          @disperse_left = @disperse_duration
          @rings.flatten.each do |ch|
            ch[:last] = ch[:cur]
            set_disperse_path(ch, @ctx.anim(ch[:id]).cur_col, @ctx.anim(ch[:id]).cur_row)
            @ctx.motion_activate_path(ch[:id], "scatter")
            @ctx.activate_scene(ch[:id], "disperse")
          end
          @phase = "disperse"
        end
      else
        @spin_left -= 1
      end
    when "final"
      @phase = "complete" if @ctx.active_empty?
    end
    @ctx.update(self)
    @rings.flatten.each do |ch|
      current = @ctx.anim(ch[:id]).active_path
      index = ch[:paths].index(current)
      ch[:cur] = index unless index.nil?
    end
    @ctx.frame_string
  end
end
