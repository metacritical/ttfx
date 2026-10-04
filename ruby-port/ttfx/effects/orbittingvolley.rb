# Faithful orbittingvolley (ttfx src/effects/orbittingvolley.rs).
#
# Four launcher characters orbit the canvas perimeter (one on a looping
# path, three positioned from its progress), firing volleys of input
# characters inward along eased paths until the text builds center-out.
# Fully deterministic (no RNG draws).
class OrbittingvolleyEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @top_sym = o.fetch("top_launcher_symbol", "\u2588")
    @right_sym = o.fetch("right_launcher_symbol", "\u2588")
    @bottom_sym = o.fetch("bottom_launcher_symbol", "\u2588")
    @left_sym = o.fetch("left_launcher_symbol", "\u2588")
    @launcher_speed = o.fetch("launcher_movement_speed", 0.8)
    @char_speed = o.fetch("character_movement_speed", 1.5)
    @volley = o.fetch("volley_size", 0.03)
    @delay_default = o.fetch("launch_delay", 30)
    @char_ease = o.fetch("character_easing", "out_sine")
    stop_hex = o.fetch("final_gradient_stops", ["FFA15C", "44D492"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "radial")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @final_map = {}
    @launcher_map = nil
    @launcher_last = nil
    @launchers = []
    @delay = 0
    @complete = false
  end

  def build_launcher_paths(id)
    cv = @ctx.canvas
    wps = [[cv.left, cv.top], [cv.right, cv.top]]
    a = @ctx.anim(id)
    start_idx = 0
    wps.each_with_index do |w, i|
      if w[0] == a.input_col && w[1] == a.input_row
        start_idx = i
      end
    end
    @ctx.motion_new_path(id, "perimeter", @launcher_speed, nil, 0, false, 2)
    tail = wps[start_idx, wps.length]
    head = wps[0, start_idx]
    (tail + head).each do |w|
      @ctx.motion_add_waypoint(id, "perimeter", w[0], w[1])
    end
  end

  def magazine_launch(lidx)
    launcher = @launchers[lidx]
    return nil if launcher[1].empty?
    id = launcher[1].shift
    la = @ctx.anim(launcher[0])
    @ctx.motion_set_coordinate(id, la.cur_col, la.cur_row)
    @ctx.motion_activate_path(id, "input_path")
    @ctx.set_visible(id, true)
    id
  end

  def set_child_coords(child_idx)
    cv = @ctx.canvas
    parent = @ctx.anim(@launchers[0][0])
    child = @ctx.anim(@launchers[child_idx][0])
    progress = parent.cur_col.to_f / cv.right.to_f
    cc = child.input_col
    cr = child.input_row
    if cc == cv.right && cr == cv.top
      r = cv.top - (cv.top.to_f * progress).to_i
      r = 1 if r < 1
      @ctx.motion_set_coordinate(child.id, cv.right, r)
    elsif cc == cv.right && cr == cv.bottom
      c = cv.right - (cv.right.to_f * progress).to_i
      c = 1 if c < 1
      @ctx.motion_set_coordinate(child.id, c, cv.bottom)
    elsif cc == cv.left && cr == cv.bottom
      r = cv.bottom + (cv.top.to_f * progress).to_i
      r = cv.top if r > cv.top
      @ctx.motion_set_coordinate(child.id, cv.left, r)
    end
    a = @ctx.anim(child.id)
    color = @launcher_map.get(a.cur_col, a.cur_row)
    @ctx.set_appearance(child.id, a.input_sym, color)
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    @launcher_map = grad.coord_map(cv.bottom, cv.top, cv.left, cv.right, @final_direction)
    @launcher_last = grad.spectrum[grad.spectrum.length - 1]
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      @final_map[id] = mapping.get(a.input_col, a.input_row)
      @ctx.motion_new_path(id, "input_path", @char_speed, @char_ease, 0, false, 1)
      @ctx.motion_add_waypoint(id, "input_path", a.input_col, a.input_row)
      @ctx.register_event(id, "path_complete", "input_path", "layer", 0)
      @ctx.set_appearance(id, a.input_sym, @final_map[id])
    end
    specs = [
      [[cv.left, cv.top], @top_sym],
      [[cv.right, cv.top], @right_sym],
      [[cv.right, cv.bottom], @bottom_sym],
      [[cv.left, cv.bottom], @left_sym]
    ]
    specs.each do |coord, sym|
      id = @ctx.add_character(sym, coord[0], coord[1])
      @ctx.anim(id).layer = 2
      @ctx.set_visible(id, true)
      @ctx.active_include(id)
      @launchers.push([id, []])
    end
    main = @launchers[0][0]
    @ctx.set_appearance(main, @ctx.anim(main).input_sym, @launcher_last)
    build_launcher_paths(main)
    @ctx.motion_activate_path(main, "perimeter")
    mags = []
    cv.grouped_ids("center_to_outside").each do |g|
      g.each { |id| mags.push(id) }
    end
    mags.each_with_index do |id, i|
      @launchers[i % @launchers.length][1].push(id)
    end
    @delay = 0
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    cv = @ctx.canvas
    any_mag = false
    @launchers.each { |l| any_mag = true unless l[1].empty? }
    if any_mag || @ctx.active.length > 1
      main = @launchers[0][0]
      if @ctx.anim(main).active_path.nil?
        wp0 = @ctx.anim(main).paths["perimeter"].waypoints[0]
        @ctx.motion_set_coordinate(main, wp0[0], wp0[1])
        @ctx.motion_activate_path(main, "perimeter")
        @ctx.active_include(main)
      end
      a = @ctx.anim(main)
      color = @launcher_map.get(a.cur_col, a.cur_row)
      @ctx.set_appearance(main, @top_sym, color)
      ci = 1
      while ci < @launchers.length
        set_child_coords(ci)
        ci += 1
      end
      if @delay == 0
        li = 0
        while li < @launchers.length
          per = ((@volley * cv.char_count.to_f) / 4.0).to_i
          per = 1 if per < 1
          per.times do
            nid = magazine_launch(li)
            @ctx.active_include(nid) unless nid.nil?
          end
          li += 1
        end
        @delay = @delay_default
      else
        @delay -= 1
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    unless @complete
      @complete = true
      @launchers.each do |l|
        @ctx.set_visible(l[0], false)
      end
      return @ctx.frame_string
    end
    nil
  end
end
