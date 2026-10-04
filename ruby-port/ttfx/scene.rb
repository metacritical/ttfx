# Faithful per-character scene machine (ttfx src/engine/animation.rs +
# src/engine/ctx.rs animation/events subset used by decrypt).
#
# No motion, no easing, no sync: scenes are plain frame queues with
# per-frame durations. SceneComplete events with a Scene caller activate the
# next scene within the same tick. Characters are active while they hold a
# non-empty scene; visibility is tracked separately and survives completion.

# One frame: symbol + fg color + duration in ticks.
class Frame
  attr_accessor :sym, :fg, :duration, :ticks

  def initialize(sym, fg, duration)
    @sym = sym
    @fg = fg
    @duration = duration
    @ticks = 0
  end
end

class Scene
  attr_reader :name, :ease_name, :total
  attr_accessor :sync_metric, :looping

  def all_frames
    @all
  end

  def frame_map
    @map
  end

  def initialize(name, ease_name = nil)
    @name = name
    @ease_name = ease_name
    @sync_metric = nil
    @looping = false
    @all = []
    @queue = []
    @head = 0
    @map = []
    @total = 0
    @estep = 0
  end

  def add_frame(sym, fg, duration)
    raise "Frame duration must be at least 1. Received: #{duration}" if duration < 1
    idx = @all.length
    @all.push(Frame.new(sym, fg, duration))
    @queue.push(idx)
    if !@ease_name.nil?
      d = 0
      while d < duration
        @map.push(idx)
        d += 1
      end
    end
    @total += duration
    self
  end

  def empty?
    @head >= @queue.length
  end

  # First frame's visual; error when empty.
  def activate
    raise "Scene #{@name} has no frames." if empty?
    f = @all[@queue[@head]]
    [f.sym, f.fg]
  end

  # Tick the head frame, retiring it at duration; returns its visual.
  # Looping scenes restore the queue when it runs out.
  def next_visual
    f = @all[@queue[@head]]
    vis = [f.sym, f.fg]
    f.ticks += 1
    if f.ticks == f.duration
      f.ticks = 0
      @head += 1
      @head = 0 if @looping && empty?
    end
    vis
  end

  # Eased stepping: visual by eased position over the duration map.
  # Returns [visual, completed?].
  def next_eased
    fin = @total - 1
    fin = 0 if fin < 0
    factor = Easing.ease(@ease_name, @estep.to_f / @total.to_f)
    fi = PyCompat.round_half_even(factor * fin.to_f)
    fi = 0 if fi < 0
    fi = fin if fi > fin
    f = @all[@map[fi]]
    @estep += 1
    [[f.sym, f.fg], @estep == @total]
  end

  # Restore original order, zero tick counters and the easing step.
  def reset
    @all.each { |f| f.ticks = 0 }
    @head = 0
    @estep = 0
  end
end

# Minimal engine context for animation-only effects (decrypt pilot).
# Owns the characters, the active set (canonical ascending-id order), the
# SceneComplete event table, and frame rendering shared by the ANSI, dump,
# and raylib backends.
# Geometry helpers (ttfx src/utils/geometry.rs).
module Geometry
  def self.lerp_point(scol, srow, ecol, erow, t)
    [(1.0 - t) * scol.to_f + t * ecol.to_f, (1.0 - t) * srow.to_f + t * erow.to_f]
  end

  # De Casteljau of arbitrary degree, rounded only at the end.
  def self.coord_on_bezier(scol, srow, control, ecol, erow, t)
    if control.nil? || control.empty?
      x = (1.0 - t) * scol.to_f + t * ecol.to_f
      y = (1.0 - t) * srow.to_f + t * erow.to_f
      return [PyCompat.round_half_even(x), PyCompat.round_half_even(y)]
    end
    pts = [[scol.to_f, srow.to_f]]
    control.each { |c| pts.push([c[0].to_f, c[1].to_f]) }
    pts.push([ecol.to_f, erow.to_f])
    remaining = pts.length
    while remaining > 1
      i = 0
      while i < remaining - 1
        pts[i] = lerp_point(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], t)
        i += 1
      end
      remaining -= 1
    end
    [PyCompat.round_half_even(pts[0][0]), PyCompat.round_half_even(pts[0][1])]
  end

  # Doubled-row line length (hypot, terminal cell aspect convention).
  def self.line_length_doubled(c1col, c1row, c2col, c2row)
    dx = (c2col - c1col).to_f
    dy = ((c2row - c1row) * 2).to_f
    Math.hypot(dx, dy)
  end

  # 10-sample polyline stopping at t=0.9 (faithful underestimate).
  def self.bezier_length(scol, srow, control, ecol, erow)
    len = 0.0
    pc = scol
    pr = srow
    t = 1
    while t < 10
      cc = coord_on_bezier(scol, srow, control, ecol, erow, t.to_f / 10.0)
      len += line_length_doubled(pc, pr, cc[0], cc[1])
      pc = cc[0]
      pr = cc[1]
      t += 1
    end
    len
  end

  # Extrapolate past target by offset (non-doubled hypot length, rounded).
  def self.extrapolate_ray(ocol, orow, tcol, trow, offset)
    dx = (tcol - ocol).to_f
    dy = (trow - orow).to_f
    base = Math.hypot(dx, dy)
    total = base + offset
    return [tcol, trow] if total == 0.0 || (ocol == tcol && orow == trow)
    t = total / base
    x = (1.0 - t) * ocol.to_f + t * tcol.to_f
    y = (1.0 - t) * orow.to_f + t * trow.to_f
    [PyCompat.round_half_even(x), PyCompat.round_half_even(y)]
  end

  # Column-major ellipse cells (diameter 0 -> empty).
  def self.coords_in_circle(h, k, diameter)
    out = []
    return out if diameter == 0
    a2 = (diameter.to_f) ** 2.0
    b2 = (diameter.to_f / 2.0) ** 2.0
    x = h - diameter
    while x <= h + diameter
      xc = (((x - h).to_f) ** 2.0) / a2
      max_y = ((b2 * (1.0 - xc)) ** 0.5).to_i
      y = k - max_y
      while y <= k + max_y
        out.push([x, y])
        y += 1
      end
      x += 1
    end
    out
  end
end

# A movement path: waypoints, segments, and stepping state.
class MotionPath
  attr_accessor :name, :speed, :ease, :hold, :loop
  attr_accessor :waypoints, :segments, :total
  attr_accessor :step, :max_steps, :hold_left, :last_dist, :origin, :origin_wp
  attr_accessor :layer

  def initialize(name, speed, ease, hold, loop_flag, layer = nil)
    @name = name
    @speed = speed
    @ease = ease
    @hold = hold
    @loop = loop_flag
    @layer = layer
    @waypoints = []
    @segments = []
    @total = 0.0
    @step = 0
    @max_steps = 0
    @hold_left = hold
    @last_dist = 0.0
    @origin = nil
    @origin_wp = nil
  end
end

class EngineCtx
  attr_reader :canvas, :rng, :chars, :active
  attr_accessor :frame_rate

  def initialize(canvas, rng)
    @canvas = canvas
    @rng = rng
    @chars = canvas.anims
    @active = []
    @events = {}
    @frame_rate = 60
    @velapsed = 0.0
    use_wall_clock
  end

  def use_virtual_clock
    @clock_mode = "virtual"
    @velapsed = 0.0
  end

  def use_wall_clock
    @clock_mode = "wall"
    begin
      @t0 = Time.now.to_f
    rescue StandardError
      @t0 = 0.0
    end
  end

  # Seconds since build (virtual: frames / frame_rate).
  def now_wall
    if @clock_mode == "virtual"
      @velapsed
    else
      begin
        Time.now.to_f - @t0
      rescue StandardError
        0.0
      end
    end
  end

  def tick_clock
    @velapsed += 1.0 / @frame_rate.to_f
  end

  def anim(id)
    @chars[id]
  end

  # Appended arena character (overflow copies).
  def add_character(sym, col, row)
    id = @chars.length
    @chars.push(CharAnim.new(id, col, row, sym))
    @chars[id].uses_preexisting_colors = false
    id
  end

  def new_scene(id, name)
    anim(id).scenes[name] = Scene.new(name)
  end

  def new_scene_eased(id, name, ease_name)
    anim(id).scenes[name] = Scene.new(name, ease_name)
  end

  def new_scene_synced(id, name, metric)
    sc = Scene.new(name)
    sc.sync_metric = metric
    anim(id).scenes[name] = sc
  end

  def new_scene_loop(id, name)
    sc = Scene.new(name)
    sc.looping = true
    anim(id).scenes[name] = sc
  end

  def scene(id, name)
    anim(id).scenes[name]
  end

  def add_frame(id, name, sym, duration, fg)
    scene(id, name).add_frame(sym, fg, duration)
  end

  # Activation does NOT reset playback (resume semantics): current visual
  # becomes the scene's first frame.
  def activate_scene(id, name)
    a = anim(id)
    vis = a.scenes[name].activate
    a.active = name
    a.cur_sym = vis[0]
    a.cur_fg = vis[1]
  end

  def set_visible(id, flag)
    anim(id).visible = flag
  end

  # Direct visual override, bypassing scenes (matrix rain appearance).
  def set_appearance(id, sym, fg)
    a = anim(id)
    a.cur_sym = sym
    a.cur_fg = fg
  end

  def deactivate_scene(id)
    anim(id).active = nil
  end

  def reset_scene(id, name)
    anim(id).scenes[name].reset
  end

  # ---- motion (paths, waypoints, per-tick movement) ----

  # Python round(): banker's rounding to Integer.
  def round_half_even(x)
    PyCompat.round_half_even(x)
  end

  # hypot with the row delta doubled (terminal cell aspect convention).
  def line_length(c1col, c1row, c2col, c2row)
    dx = (c2col - c1col).to_f
    dy = ((c2row - c1row) * 2).to_f
    Math.hypot(dx, dy)
  end

  # Lerp + banker's rounding to integer coords.
  def coord_on_line(scol, srow, ecol, erow, t)
    x = (1.0 - t) * scol.to_f + t * ecol.to_f
    y = (1.0 - t) * srow.to_f + t * erow.to_f
    [round_half_even(x), round_half_even(y)]
  end

  def motion_set_coordinate(id, col, row)
    a = anim(id)
    a.cur_col = col
    a.cur_row = row
  end

  def motion_new_path(id, name, speed, ease, hold, loop_flag, layer = nil)
    raise "Path speed must be greater than 0. Received: #{speed}" unless speed > 0.0
    pname = name
    if pname.empty?
      n = anim(id).paths.length
      while anim(id).paths.key?(n.to_s)
        n += 1
      end
      pname = n.to_s
    end
    anim(id).paths[pname] = MotionPath.new(pname, speed, ease, hold, loop_flag, layer)
    pname
  end

  def motion_add_waypoint(id, pname, col, row, control = nil)
    p = anim(id).paths[pname]
    ctrl = nil
    unless control.nil? || control.empty?
      ctrl = control
    end
    p.waypoints.push([col, row, ctrl])
    return if p.waypoints.length < 2
    prev = p.waypoints[p.waypoints.length - 2]
    if ctrl.nil?
      d = line_length(prev[0], prev[1], col, row)
    else
      d = Geometry.bezier_length(prev[0], prev[1], ctrl, col, row)
    end
    p.total += d
    e = p.waypoints.length - 1
    p.segments.push([e - 1, e, d])
    p.max_steps = round_half_even(p.total / p.speed)
  end

  # Replace a one-waypoint target while retaining the path's speed/easing.
  # Rings uses one retargeted orbit path per character instead of allocating
  # a distinct path for every angular coordinate.
  def motion_retarget_path(id, pname, col, row)
    p = anim(id).paths[pname]
    p.waypoints = [[col, row, nil]]
    p.segments = []
    p.total = 0.0
    p.max_steps = 0
    p.origin = nil
    p.origin_wp = nil
    motion_add_waypoint(id, pname, col, row)
  end

  def motion_activate_path(id, pname)
    a = anim(id)
    p = a.paths[pname]
    raise "activate_path: empty path #{pname}" if p.waypoints.empty?
    first = p.waypoints[0]
    if first[2].nil?
      d = line_length(a.cur_col, a.cur_row, first[0], first[1])
    else
      d = Geometry.bezier_length(a.cur_col, a.cur_row, first[2], first[0], first[1])
    end
    if p.origin.nil?
      p.segments.unshift([-1, 0, d])
    else
      p.total -= p.origin[2]
      p.segments[0] = [-1, 0, d]
    end
    p.origin = [-1, 0, d]
    p.origin_wp = [a.cur_col, a.cur_row]
    p.total += d
    a.active_path = pname
    p.step = 0
    p.hold_left = p.hold
    p.max_steps = round_half_even(p.total / p.speed)
    a.layer = p.layer unless p.layer.nil?
    fire_event(id, "path_activated", pname)
  end

  def motion_deactivate_path(id, pname)
    a = anim(id)
    a.active_path = nil if pname.nil? || a.active_path == pname
  end

  def motion_move(id, effect = nil)
    a = anim(id)
    pname = a.active_path
    return if pname.nil?
    p = a.paths[pname]
    return if p.segments.empty?
    coord = path_step(p, a)
    a.cur_col = coord[0]
    a.cur_row = coord[1]
    return unless p.step == p.max_steps
    if p.hold != 0 && p.hold_left == p.hold
      p.hold_left -= 1
      return
    end
    if p.hold_left != 0
      p.hold_left -= 1
      return
    end
    if p.loop && p.segments.length > 1
      motion_deactivate_path(id, pname)
      motion_activate_path(id, pname)
    else
      motion_deactivate_path(id, pname)
      fire_event(id, "path_complete", pname, effect)
    end
  end

  # One step along the path; returns [col, row].
  def path_step(p, a)
    if p.max_steps == 0 || p.step >= p.max_steps || p.total == 0.0
      last = p.waypoints[p.waypoints.length - 1]
      return [last[0], last[1]]
    end
    p.step += 1
    ratio = p.step.to_f / p.max_steps.to_f
    factor = p.ease.nil? ? ratio : Easing.ease(p.ease, ratio)
    dist = factor * p.total
    p.last_dist = dist
    left = dist
    idx = nil
    i = 0
    while i < p.segments.length
      seg = p.segments[i]
      if left <= seg[2]
        idx = i
        break
      end
      left -= seg[2]
      i += 1
    end
    if idx.nil?
      idx = p.segments.length - 1
      left += p.segments[idx][2]
    end
    seg = p.segments[idx]
    t = 0.0
    if seg[2] != 0.0
      t = left / seg[2]
      t = 1.0 if t > 1.0 && p.ease.nil?
    end
    s = seg_start(p, seg[0])
    e = p.waypoints[seg[1]]
    if e[2].nil?
      coord_on_line(s[0], s[1], e[0], e[1], t)
    else
      Geometry.coord_on_bezier(s[0], s[1], e[2], e[0], e[1], t)
    end
  end

  def chain_paths(id, names, loop_flag)
    return if names.length < 2
    i = 1
    while i < names.length
      register_event(id, "path_complete", names[i - 1], "path", names[i])
      i += 1
    end
    if loop_flag
      register_event(id, "path_complete", names[names.length - 1], "path", names[0])
    end
  end

  def seg_start(p, seg_ref)
    return p.origin_wp if seg_ref == -1
    p.waypoints[seg_ref]
  end

  def active_include(id)
    @active.push(id) unless @active.include?(id)
  end

  def active_snapshot
    @active.sort
  end

  def active_clear
    @active = []
  end

  def active_empty?
    @active.empty?
  end

  def register_event(id, kind, caller_name, action_type, action_value)
    list = @events[id]
    if list.nil?
      list = []
      @events[id] = list
    end
    list.push([kind, caller_name, action_type, action_value])
  end

  def fire_scene_complete(id, caller_scene, effect = nil)
    fire_event(id, "scene_complete", caller_scene, effect)
  end

  def fire_event(id, kind, caller_name, effect = nil)
    list = @events[id]
    return if list.nil?
    list.each do |k, caller, atype, avalue|
      next unless k == kind && caller == caller_name
      if atype == "scene"
        activate_scene(id, avalue)
      elsif atype == "layer"
        anim(id).layer = avalue
      elsif atype == "deactivate_scene"
        deactivate_scene(id)
      elsif atype == "path"
        motion_activate_path(id, avalue)
      elsif atype == "callback"
        effect.on_callback(self, id, avalue) unless effect.nil?
      end
    end
  end

  def clear_char_events(id)
    @events.delete(id)
  end

  # Scene.apply_gradient_to_symbols with the exact cyclic_distribution
  # generator semantics. pairs: array of [fg, bg] (either may be nil).
  def cyclic_pairs(larger, smaller)
    rf = larger.length / smaller.length
    oc = larger.length % smaller.length
    used = false
    si = 0
    rep = 0
    out = []
    larger.each do |el|
      if rep >= rf
        if oc > 0
          if used
            si += 1
            rep = 0
            used = false
          else
            used = true
            oc -= 1
          end
        else
          si += 1
          rep = 0
        end
      end
      rep += 1
      out.push([el, smaller[si]])
    end
    out
  end

  def apply_gradient(id, scene_name, symbols, duration, pairs)
    if symbols.length >= pairs.length
      cyclic_pairs(symbols, pairs).each do |sym, pr|
        add_frame(id, scene_name, sym, duration, pr[0])
      end
    else
      cyclic_pairs(pairs, symbols).each do |pr, sym|
        add_frame(id, scene_name, sym, duration, pr[0])
      end
    end
  end

  def step_animation(id, effect = nil)
    a = anim(id)
    return if a.active.nil?
    sc = a.scenes[a.active]
    return if sc.nil? || sc.empty?
    unless sc.sync_metric.nil?
      step_synced(id, a, sc, effect)
      return
    end
    if sc.ease_name.nil?
      vis = sc.next_visual
      a.cur_sym = vis[0]
      a.cur_fg = vis[1]
      if sc.empty?
        sc.reset
        done = a.active
        a.active = nil
        fire_scene_complete(id, done, effect)
      end
    else
      vis, done = sc.next_eased
      a.cur_sym = vis[0]
      a.cur_fg = vis[1]
      if done
        sc.reset
        aname = a.active
        a.active = nil
        fire_scene_complete(id, aname, effect)
      end
    end
  end

  # Synced scene stepping: visual follows path progress; frames never
  # drain. With no active path, jumps to the final frame and completes.
  def step_synced(id, a, sc, effect = nil)
    pname = a.active_path
    if pname.nil?
      last_idx = sc.all_frames.length - 1
      last_idx = 0 if last_idx < 0
      f = sc.all_frames[last_idx]
      a.cur_sym = f.sym
      a.cur_fg = f.fg
      sc.reset
      aname = a.active
      a.active = nil
      fire_scene_complete(id, aname, effect)
      return
    end
    p = a.paths[pname]
    ratio = 0.0
    if sc.sync_metric == "step"
      denom = p.max_steps < 1 ? 1 : p.max_steps
      num = p.step < 1 ? 1 : p.step
      ratio = num.to_f / denom.to_f
    else
      total = p.total < 1.0 ? 1.0 : p.total
      remaining = p.total - p.last_dist
      remaining = 1.0 if remaining < 1.0
      reached = total - remaining
      reached = 1.0 if reached < 1.0
      ratio = reached / total
    end
    fin = sc.all_frames.length - 1
    fin = 0 if fin < 0
    fi = PyCompat.round_half_even(ratio * fin.to_f)
    fi = 0 if fi < 0
    fi = fin if fi > fin
    f = sc.all_frames[fi]
    a.cur_sym = f.sym
    a.cur_fg = f.fg
  end

  def char_active?(id)
    a = anim(id)
    return true unless a.active_path.nil?
    return false if a.active.nil?
    sc = a.scenes[a.active]
    return false if sc.nil?
    return false if sc.looping
    !sc.empty?
  end

  # Tick a snapshot of actives in ascending-id order, then prune finished.
  # Motion runs before animation within each tick.
  def update(effect = nil)
    snap = @active.sort
    snap.each do |id|
      motion_move(id, effect)
      step_animation(id, effect)
    end
    @active = @active.select { |id| char_active?(id) }
  end

  # Frame string: row-major over rows 1..visible_top, columns
  # 1..visible_right (absolute coordinates, top row first); cells outside
  # the visible window render as spaces. These are the exact bytes the old
  # engine's formatted output produces (what --parity-dump compares).
  def frame_string
    cv = @canvas
    grid = {}
    @chars.each do |a|
      next unless a.visible
      r = a.cur_row + cv.row_offset
      c = a.cur_col + cv.col_offset
      next unless r >= cv.visible_bottom && r <= cv.visible_top
      next unless c >= cv.visible_left && c <= cv.visible_right
      key = r * 1000000 + c
      prev = grid[key]
      if prev.nil? || a.layer > prev.layer || (a.layer == prev.layer && a.id > prev.id)
        grid[key] = a
      end
    end
    rows = []
    r = cv.visible_top
    while r >= 1
      parts = []
      c = 1
      while c <= cv.visible_right
        a = grid[r * 1000000 + c]
        if a.nil?
          parts.push(" ")
        else
          parts.push(format_cell(a.cur_sym, a.cur_fg))
        end
        c += 1
      end
      rows.push(parts.join)
      r -= 1
    end
    rows.join("\n")
  end

  def format_cell(sym, fg)
    return sym if fg.nil?
    Color.fg(fg) + sym + Color::RESET
  end

  # Cell list for the raylib backend: [row1, col1, sym, r, g, b] in
  # 1-based bottom-up terminal coordinates (offsets applied).
  def frame_cells
    cv = @canvas
    cells = []
    @chars.each do |a|
      next unless a.visible
      r = a.cur_row + cv.row_offset
      c = a.cur_col + cv.col_offset
      next unless r >= cv.visible_bottom && r <= cv.visible_top
      next unless c >= cv.visible_left && c <= cv.visible_right
      if a.cur_fg.nil?
        cells.push([r, c, a.cur_sym, 255, 255, 255])
      else
        cells.push([r, c, a.cur_sym, a.cur_fg[0], a.cur_fg[1], a.cur_fg[2]])
      end
    end
    cells
  end
end
