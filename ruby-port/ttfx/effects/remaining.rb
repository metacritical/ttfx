# Ruby ports of the remaining scene-engine effects. Each effect follows the
# corresponding Rust effect's high-level phases and uses the shared scene,
# motion, RNG, gradient, and canvas implementations.

class RemainingEffect
  def initialize(ctx, opts = {})
    @ctx = ctx
    @opts = opts || {}
  end

  def chars
    @ctx.canvas.ordered_ids
  end

  # Rust Terminal.get_characters sort variants used by the remaining effects.
  def rust_order(kind = :top)
    ids = @ctx.canvas.ordered_ids
    case kind
    when :bottom_right then ids.reverse
    when :bottom_left then ids.sort_by { |id| [@ctx.anim(id).input_row, @ctx.anim(id).input_col] }
    when :top_right then ids.reverse.sort_by { |id| [-@ctx.anim(id).input_row, -@ctx.anim(id).input_col] }
    else ids
    end
  end

  def gradient(stops, steps = [12], direction = "vertical")
    g = Gradient.build(stops.map { |c| c.is_a?(String) ? Color.from_hex(c) : c }, steps, false, false)
    cv = @ctx.canvas
    [g, g.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, direction)]
  end

  def color_frames(id, name, sym, colors, duration = 2)
    colors.each { |c| @ctx.add_frame(id, name, sym, duration, c) }
  end

  def set_home(id, mapping)
    a = @ctx.anim(id)
    @ctx.set_appearance(id, a.input_sym, mapping.get(a.input_col, a.input_row))
    @ctx.set_visible(id, true)
  end

  def move_path(id, name, speed, ease, coords)
    @ctx.motion_new_path(id, name, speed, ease, 0, false)
    coords.each { |c, r| @ctx.motion_add_waypoint(id, name, c, r) }
    @ctx.motion_activate_path(id, name)
    @ctx.active_include(id)
  end

  def draw_tick
    @ctx.update(self)
    @ctx.frame_string
  end

  def complete_when_idle
    @ctx.active_empty?
  end
end

# Swarm: cohorts leave a common spawn, visit focus areas, then settle home.
class SwarmEffect < RemainingEffect
  def build
    @ids=rust_order
    @mapping=gradient(@opts.fetch("final_gradient_stops",["31b900","f0ff65"]),@opts.fetch("final_gradient_steps",[12]),@opts.fetch("final_gradient_direction","horizontal"))[1]
    ratio=@opts.fetch("swarm_size",0.1).to_f
    size=[PyCompat.round_half_even(@ids.length*ratio),1].max
    unswarmed=rust_order(:bottom_right)
    @swarms=[]
    until unswarmed.empty?
      @swarms << unswarmed.pop(size)
    end
    last=@swarms.pop || []
    if last.length < size.div(2) && !@swarms.empty?
      @swarms[-1].concat(last)
    else
      @swarms << last
    end
    @coordination=@opts.fetch("swarm_coordination",0.8).to_f
    @area_range=@opts.fetch("swarm_area_count_range",[2,4])
    @base_colors=@opts.fetch("base_color",["31a0d4"]).map{|c|Color.from_hex(c)}
    @flash=Color.from_hex(@opts.fetch("flash_color","f2ea79"))
    @circle_cache={}
    @swarms.each do |swarm|
      base=@ctx.rng.choice(@base_colors)
      spectrum=Gradient.with_steps([base,@flash],7,false).spectrum
      flash_spectrum=spectrum + Array.new(10,@flash) + spectrum.reverse
      spawn=@ctx.canvas.random_coord(@ctx.rng,true,false)
      area_count=@ctx.rng.randint(@area_range[0],@area_range[1])
      area_map=[]
      areas=[]
      last_focus=spawn
      radius=[[@ctx.canvas.right,@ctx.canvas.top].min.div(2),1].max
      while areas.length < area_count
        cached=(@circle_cache[last_focus] ||= @ctx.canvas.find_coords_on_circle(last_focus[0],last_focus[1],radius,0,true))
        @ctx.rng.shuffle(cached)
        nxt=cached.find{|c,r| c>=@ctx.canvas.left && c<=@ctx.canvas.right && r>=@ctx.canvas.bottom && r<=@ctx.canvas.top}
        nxt ||= @ctx.canvas.random_coord(@ctx.rng,false,false)
        areas << nxt
        diameter=[[@ctx.canvas.right,@ctx.canvas.top].min.div(6),1].max*2
        coords=Geometry.coords_in_circle(last_focus[0],last_focus[1],diameter)
        entry=area_map.find{|c,v|c==last_focus}
        entry ? entry[1]=coords : area_map << [last_focus,coords]
        last_focus=nxt
      end
      swarm.each do |id|
        a=@ctx.anim(id)
        @ctx.motion_set_coordinate(id,spawn[0],spawn[1])
        @ctx.new_scene_synced(id,"swarm_flash","distance")
        flash_spectrum.each{|c|@ctx.add_frame(id,"swarm_flash",a.input_sym,1,c)}
        path_names=[]
        area_map.each_with_index do |(_focus,coords),area_index|
          area_name="#{area_index}_swarm_area"
          origin=@ctx.rng.choice(coords)
          pn=@ctx.motion_new_path(id,area_name,0.4,"out_sine",0,false)
          @ctx.motion_add_waypoint(id,pn,origin[0],origin[1]);path_names<<pn
          @ctx.register_event(id,"path_activated",pn,"scene","swarm_flash")
          @ctx.register_event(id,"path_activated",pn,"layer",1)
          @ctx.register_event(id,"path_complete",pn,"deactivate_scene",nil)
          2.times do
            target=@ctx.rng.choice(coords)
            ip=@ctx.motion_new_path(id,"",0.18,"in_out_sine",0,false)
            @ctx.motion_add_waypoint(id,ip,target[0],target[1]);path_names<<ip
          end
        end
        ip=@ctx.motion_new_path(id,"",0.45,"in_out_quad",0,false)
        @ctx.motion_add_waypoint(id,ip,a.input_col,a.input_row);path_names<<ip
        @ctx.new_scene(id,"swarm_home")
        final=@mapping.get(a.input_col,a.input_row)
        Gradient.with_steps([@flash,final],10,false).spectrum.each{|c|@ctx.add_frame(id,"swarm_home",a.input_sym,3,c)}
        @ctx.register_event(id,"path_complete",ip,"scene","swarm_home")
        @ctx.register_event(id,"path_complete",ip,"layer",0)
        @ctx.register_event(id,"path_activated",ip,"scene","swarm_flash")
        @ctx.chain_paths(id,path_names,false)
        @ctx.set_appearance(id,a.input_sym,final)
      end
    end
    @call_next=true
    @active_area="0_swarm_area"
    @current=[]
  end

  def next_frame
    return nil if @swarms.empty? && @ctx.active_empty?
    if !@swarms.empty? && @call_next
      @call_next=false
      @current=@swarms.pop
      @active_area="0_swarm_area"
      @current.each do |id|
        @ctx.motion_activate_path(id,"0_swarm_area")
        @ctx.set_visible(id,true);@ctx.active_include(id)
      end
    end
    @call_next=true if @ctx.active.length < @current.length
    unless @current.empty?
      @current.each do |id|
        active=@ctx.anim(id).active_path
        next if active.nil? || active==@active_area || !active.include?("swarm_area")
        if active[0].to_i > @active_area[0].to_i
          @active_area=active
          @current.each do |other|
            next if other==id
            @ctx.motion_activate_path(other,@active_area) if @ctx.rng.random < @coordination
          end
          break
        end
      end
    end
    @ctx.update(self)
    @ctx.frame_string
  end
end

# Crumble mirrors the Rust Falling -> Vacuuming -> Resetting stages. Per
# character scenes and paths are event chained, so the dust and flash follow
# the same motion lifecycle as the reference engine.
class CrumbleEffect < RemainingEffect
  def build
    @ids = rust_order
    @mapping = gradient(@opts.fetch("final_gradient_stops", ["5CE1FF", "FF8C00"]), @opts.fetch("final_gradient_steps", [12]), @opts.fetch("final_gradient_direction", "diagonal"))[1]
    cv = @ctx.canvas
    @ids.each do |id|
      a = @ctx.anim(id)
      final = @mapping.get(a.input_col, a.input_row)
      weak = Color.adjust_brightness(final, 0.65)
      dust = Color.adjust_brightness(final, 0.55)
      @ctx.set_visible(id, true)
      @ctx.new_scene(id, "initial"); @ctx.add_frame(id, "initial", a.input_sym, 1, weak); @ctx.activate_scene(id, "initial")
      @ctx.new_scene(id, "weaken")
      Gradient.with_steps([weak, dust], 9, false).spectrum.each { |color| @ctx.add_frame(id, "weaken", a.input_sym, 4, color) }
      @ctx.new_scene_synced(id, "dust", "distance")
      5.times { @ctx.add_frame(id, "dust", @ctx.rng.choice(["*", ".", ","]), 1, dust) }
      @ctx.new_scene(id, "strengthen_flash")
      Gradient.with_steps([final, Color.from_hex("ffffff")], 6, false).spectrum.each { |color| @ctx.add_frame(id, "strengthen_flash", a.input_sym, 4, color) }
      @ctx.new_scene(id, "strengthen")
      Gradient.with_steps([Color.from_hex("ffffff"), final], 9, false).spectrum.each { |color| @ctx.add_frame(id, "strengthen", a.input_sym, 4, color) }
      @ctx.motion_new_path(id, "fall", 0.65, "out_bounce", 0, false)
      @ctx.motion_add_waypoint(id, "fall", a.input_col, cv.bottom)
      @ctx.motion_new_path(id, "top", 1.0, "out_quint", 0, false)
      @ctx.motion_add_waypoint(id, "top", a.input_col, cv.top, [[cv.center_column, cv.center_row]])
      @ctx.motion_new_path(id, "input", 1.0, nil, 0, false)
      @ctx.motion_add_waypoint(id, "input", a.input_col, a.input_row)
      @ctx.register_event(id, "scene_complete", "weaken", "path", "fall")
      @ctx.register_event(id, "scene_complete", "weaken", "layer", 1)
      @ctx.register_event(id, "scene_complete", "weaken", "scene", "dust")
      @ctx.register_event(id, "path_complete", "input", "scene", "strengthen_flash")
      @ctx.register_event(id, "scene_complete", "strengthen_flash", "scene", "strengthen")
    end
    @pending = @ids.dup
    @ctx.rng.shuffle(@pending)
    @unvacuumed = @ids.dup
    @ctx.rng.shuffle(@unvacuumed)
    @fall_delay = @max_fall_delay = 12
    @min_fall_delay = 9
    @group_max = 1
    @phase = :fall
    @reset_started = false
    @done_frame = false
  end

  def next_frame
    return nil if @phase == :done && @done_frame
    if @phase == :fall
      if !@pending.empty?
        if @fall_delay.zero?
          @ctx.rng.randint(1, @group_max).times do
            break if @pending.empty?
            id = @pending.shift
            @ctx.activate_scene(id, "weaken")
            @ctx.active_include(id)
          end
          @fall_delay = @ctx.rng.randint(@min_fall_delay, @max_fall_delay)
          if @ctx.rng.randint(1, 10) > 4
            @group_max += 1
            @min_fall_delay = [@min_fall_delay - 1, 0].max
            @max_fall_delay = [@max_fall_delay - 1, 0].max
          end
        else
          @fall_delay -= 1
        end
      elsif @ctx.active_empty?
        @phase = :vacuum
      end
    elsif @phase == :vacuum
      unless @unvacuumed.empty?
        @ctx.rng.randint(3, 10).times do
          break if @unvacuumed.empty?
          id = @unvacuumed.shift
          @ctx.motion_activate_path(id, "top")
          @ctx.active_include(id)
        end
      end
      @phase = :reset if @ctx.active_empty?
    elsif @phase == :reset && !@reset_started
      @reset_started = true
      @ids.each { |id| @ctx.motion_activate_path(id, "input"); @ctx.active_include(id) }
    elsif @phase == :reset && @ctx.active_empty?
      @phase = :done
    end
    @done_frame = true if @phase == :done
    draw_tick
  end
end

# Unstable: jumbled layout rumbles, bursts to the edges, then reassembles.
class UnstableEffect < RemainingEffect
  def build
    @ids = rust_order
    @mapping = gradient(@opts.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"]), @opts.fetch("final_gradient_steps", [12]), @opts.fetch("final_gradient_direction", "vertical"))[1]
    coords = @ids.map { |id| [@ctx.anim(id).input_col, @ctx.anim(id).input_row] }
    @jumbled = {}
    @ids.each do |id|
      edge = @ctx.rng.randint(0, 3)
      case edge
      when 0 then target = [@ctx.canvas.left, @ctx.rng.randint(@ctx.canvas.bottom, @ctx.canvas.top)]
      when 1 then target = [@ctx.canvas.right, @ctx.rng.randint(@ctx.canvas.bottom, @ctx.canvas.top)]
      when 2 then target = [@ctx.rng.randint(@ctx.canvas.left, @ctx.canvas.right), @ctx.canvas.bottom]
      else target = [@ctx.rng.randint(@ctx.canvas.left, @ctx.canvas.right), @ctx.canvas.top]
      end
      home = coords.delete_at(@ctx.rng.randint(0, coords.length - 1))
      @jumbled[id] = home
      a = @ctx.anim(id)
      @ctx.motion_set_coordinate(id, home[0], home[1])
      @ctx.new_scene(id, "rumble")
      Gradient.with_steps([@mapping.get(a.input_col, a.input_row), Color.from_hex("ff9200")], 12, false).spectrum.each do |color|
        @ctx.add_frame(id, "rumble", a.input_sym, 10, color)
      end
      @ctx.new_scene(id, "settle")
      Gradient.with_steps([Color.from_hex("ff9200"), @mapping.get(a.input_col, a.input_row)], 12, false).spectrum.each do |color|
        @ctx.add_frame(id, "settle", a.input_sym, 3, color)
      end
      @ctx.motion_new_path(id, "explode", @opts.fetch("explosion_speed", 1.0).to_f, @opts.fetch("explosion_ease", "out_expo"), 0, false)
      @ctx.motion_add_waypoint(id, "explode", target[0], target[1])
      @ctx.motion_new_path(id, "reassemble", @opts.fetch("reassembly_speed", 1.0).to_f, @opts.fetch("reassembly_ease", "out_expo"), 0, false)
      @ctx.motion_add_waypoint(id, "reassemble", a.input_col, a.input_row)
      @ctx.set_appearance(id, a.input_sym, @mapping.get(a.input_col, a.input_row))
      @ctx.set_visible(id, true)
      @ctx.activate_scene(id, "rumble")
    end
    @phase = :rumble
    @ticks = 0
    @hold = 30
    @rumble_delay = 18
  end

  def next_frame
    if @phase == :rumble
      if @ticks < 150
        if @ticks > 30 && (@ticks % @rumble_delay).zero?
          dr = @ctx.rng.choice([-1, 0, 1]); dc = @ctx.rng.choice([-1, 0, 1])
          @ids.each { |id| a = @ctx.anim(id); @ctx.motion_set_coordinate(id, a.cur_col + dc, a.cur_row + dr) }
          @ids.each { |id| @ctx.step_animation(id, self) }
          frame = @ctx.frame_string
          @ids.each { |id| p = @jumbled[id]; @ctx.motion_set_coordinate(id, p[0], p[1]) }
          @rumble_delay = [@rumble_delay - 1, 1].max
          @ticks += 1
          return frame
        end
        @ids.each { |id| @ctx.step_animation(id, self) }
        @ticks += 1
        return @ctx.frame_string
      end
      @phase = :explode
      @ids.each { |id| @ctx.motion_activate_path(id, "explode"); @ctx.active_include(id) }
    end
    if @phase == :explode
      unless @ctx.active_empty?
        @ctx.update(self)
        @ctx.active.delete_if { |id| a = @ctx.anim(id); a.cur_col == a.paths["explode"].waypoints.last[0] && a.cur_row == a.paths["explode"].waypoints.last[1] }
        return @ctx.frame_string
      end
      if @hold > 0
        @hold -= 1
        return @ctx.frame_string
      end
      @phase = :settle
      @ids.each { |id| @ctx.activate_scene(id, "settle"); @ctx.motion_activate_path(id, "reassemble"); @ctx.active_include(id) }
    end
    if @phase == :settle
      unless @ctx.active_empty?
        @ctx.update(self)
        @ctx.active.delete_if do |id|
          a = @ctx.anim(id); dest = a.paths["reassemble"].waypoints.last
          a.cur_col == dest[0] && a.cur_row == dest[1] && a.active.nil?
        end
        return @ctx.frame_string
      end
      @phase = :done
    end
    nil
  end
end

# Laseretch: a laser head scans the tree order and etches the input in place.
class LaseretchEffect < RemainingEffect
  def build
    @ids = rust_order
    @mapping = gradient(@opts.fetch("final_gradient_stops", ["8A008A", "00D1FF", "ffffff"]), @opts.fetch("final_gradient_steps", [8]), @opts.fetch("final_gradient_direction", "vertical"))[1]
    @cool_stops = @opts.fetch("cool_gradient_stops", ["ffe680", "ff7b00"]).map { |c| Color.from_hex(c) }
    @spark_stops = @opts.fetch("spark_gradient_stops", ["ffffff", "ffe680", "ff7b00", "1a0900"]).map { |c| Color.from_hex(c) }
    @laser_stops = @opts.fetch("laser_gradient_stops", ["ffffff", "376cff"]).map { |c| Color.from_hex(c) }
    @cooling_frames = @opts.fetch("spark_cooling_frames", 7).to_i
    @speed = @opts.fetch("etch_speed", 1).to_i
    @delay_setting = @opts.fetch("etch_delay", 1).to_i
    @spark_gradient = Gradient.build(@spark_stops, [3, 8], false, false).spectrum
    @ids.each do |id|
      a = @ctx.anim(id)
      final = @mapping.get(a.input_col, a.input_row)
      @ctx.new_scene(id, "spawn")
      @ctx.add_frame(id, "spawn", "^", 3, Color.from_hex("ffe680"))
      cool = @cool_stops + [final]
      Gradient.with_steps(cool, 8, false).spectrum.each { |c| @ctx.add_frame(id, "spawn", a.input_sym, 3, c) }
      @ctx.activate_scene(id, "spawn")
      @ctx.set_visible(id, false)
    end
    @pending = []
    if @opts.fetch("etch_pattern", "algorithm") == "algorithm"
      start = SpanningTree.default_starting_char(@ctx, true)
      algo = RecursiveBacktracker.new(@ctx, start, true)
      until algo.complete
        algo.step(@ctx)
      end
      @pending = algo.char_link_order
    end
    @spark_pool = []
    @spark_available = []
    @spark_active = []
    2000.times do
      sym = @ctx.rng.choice([".", ",", "*"])
      id = @ctx.add_character(sym, 0, 0)
      @ctx.anim(id).layer = 2
      @ctx.new_scene(id, "spark")
      @spark_gradient.each { |c| @ctx.add_frame(id, "spark", sym, @cooling_frames, c) }
      @spark_pool << id
      @spark_available << id
    end
    laser_gradient = Gradient.build(@laser_stops, [6], true, true).spectrum
    @beam_ids = []
    row = 0
    col = 0
    while row <= @ctx.canvas.top
      sym = @beam_ids.empty? ? "*" : "/"
      id = @ctx.add_character(sym, col, row)
      a = @ctx.anim(id); a.layer = 2; a.visible = true
      @ctx.new_scene_loop(id, "laser")
      laser_gradient.each { |c| @ctx.add_frame(id, "laser", sym, 3, c) }
      @ctx.activate_scene(id, "laser")
      @beam_ids << id
      laser_gradient = laser_gradient.rotate(1)
      row += 1; col += 1
    end
    @head_position = [0, 0]
    @delay = 0
    @beam_ids.each { |id| @ctx.active_include(id) }
    @step_size = @opts.fetch("etch_speed", 1).to_i
    @delay_setting = @opts.fetch("etch_delay", 1).to_i
  end

  def emit_spark(position)
    return if @spark_available.empty?
    id = @spark_available.pop
    @spark_active << id
    @ctx.set_visible(id, true)
    a = @ctx.anim(id)
    a.active = nil; a.active_path = nil; a.paths.clear
    @ctx.motion_set_coordinate(id, position[0], position[1])
    @ctx.reset_scene(id, "spark")
    @ctx.activate_scene(id, "spark")
    @ctx.motion_new_path(id, "", 0.3, "out_sine", 0, false)
    pname = a.paths.keys.last
    tx = @ctx.rng.randint(position[0] - 20, position[0] + 20)
    ty = @ctx.canvas.bottom
    control = [tx, position[1] + @ctx.rng.randint(-10, 20)]
    @ctx.motion_add_waypoint(id, pname, tx, ty, [control])
    @ctx.motion_activate_path(id, pname)
    @ctx.active_include(id)
  end

  def on_callback(_ctx, id, _callback)
    return unless @spark_active.include?(id)
    @spark_active.delete(id)
    @ctx.set_visible(id, false)
    a = @ctx.anim(id)
    a.active = nil; a.active_path = nil
    @ctx.active.delete(id)
    @spark_available << id unless @spark_available.include?(id)
  end

  def next_frame
    return nil if @pending.empty? && @ctx.active_empty?
    if @delay.zero?
      @step_size.times do
        break if @pending.empty?
        id = @pending.shift
        while @ctx.anim(id).input_sym == " " && @ctx.anim(id).cur_fg.nil? && !@pending.empty?
          id = @pending.shift
        end
        @ctx.set_visible(id, true)
        @ctx.active_include(id)
        a = @ctx.anim(id)
        @head_position = [a.input_col, a.input_row]
        @beam_ids.each_with_index do |bid, i|
          @ctx.motion_set_coordinate(bid, a.input_col + i, a.input_row + i)
        end
        emit_spark(@head_position)
      end
      @delay = @delay_setting
    else
      @delay -= 1
    end
    if !@pending.empty?
      @beam_ids.each { |id| @ctx.active_include(id) }
    else
      @beam_ids.each { |id| @ctx.set_visible(id, false) }
    end
    @ctx.update(self)
    @ctx.frame_string
  end
end

# Bubbles: grouped characters rise around a moving bubble anchor, pop, then
# return to their home coordinates through the final gradient.
class BubblesEffect < RemainingEffect
  def build
    opts = @opts
    @mapping = gradient(opts.fetch("final_gradient_stops", ["d33aff", "02ff7f"]), opts.fetch("final_gradient_steps", [12]), opts.fetch("final_gradient_direction", "diagonal"))[1]
    @pop_color = Color.from_hex(opts.fetch("pop_color", "ffffff"))
    @speed = opts.fetch("bubble_speed", 0.5).to_f
    @bubble_delay = opts.fetch("bubble_delay", 20).to_i
    @pop_condition = opts.fetch("pop_condition", "row")
    @easing = opts.fetch("movement_easing", "in_out_sine")
    @ids = rust_order
    @ids.each do |id|
      a = @ctx.anim(id)
      final = @mapping.get(a.input_col, a.input_row)
      @ctx.anim(id).layer = 1
      @ctx.new_scene(id, "pop_1"); @ctx.add_frame(id, "pop_1", "*", 9, @pop_color)
      @ctx.new_scene(id, "pop_2"); @ctx.add_frame(id, "pop_2", "'", 9, @pop_color)
      @ctx.new_scene(id, "final")
      Gradient.with_steps([@pop_color, final], 8, false).spectrum.each { |color| @ctx.add_frame(id, "final", a.input_sym, 6, color) }
      @ctx.register_event(id, "scene_complete", "pop_1", "scene", "pop_2")
      @ctx.register_event(id, "scene_complete", "pop_2", "scene", "final")
      @ctx.motion_new_path(id, "final", 0.3, "in_out_expo", 0, false)
      @ctx.motion_add_waypoint(id, "final", a.input_col, a.input_row)
      @ctx.register_event(id, "path_complete", "final", "layer", 0)
      @ctx.set_visible(id, false)
    end

    unbubbled = rust_order(:bottom_left)
    @bubbles = []
    until unbubbled.empty?
      count = if unbubbled.length < 5
        unbubbled.length
      else
        @ctx.rng.randint(5, [unbubbled.length, 20].min)
      end
      members = unbubbled.shift(count)
      origin = [@ctx.rng.randint(@ctx.canvas.left, @ctx.canvas.right), @ctx.canvas.top + 10]
      @bubbles << make_bubble(members, origin)
    end
    @animating = []
    @steps_since = 0
  end

  def make_bubble(members, origin)
    radius = [members.length.div(5), 1].max
    anchor = @ctx.add_character(" ", origin[0], origin[1])
    lowest = @pop_condition == "row" ? members.map { |id| @ctx.anim(id).input_row }.min : @ctx.canvas.bottom
    pts = @ctx.canvas.find_coords_on_circle(origin[0], origin[1], radius, members.length, false)
    members.each_with_index { |id, i| @ctx.motion_set_coordinate(id, pts[i][0], pts[i][1]) if pts[i] }
    @ctx.motion_new_path(anchor, "", @speed, nil, 0, false)
    target_col = @ctx.rng.randint(@ctx.canvas.left, @ctx.canvas.right)
    path_name = @ctx.anim(anchor).paths.keys.last
    @ctx.motion_add_waypoint(anchor, path_name, target_col, lowest)
    @ctx.motion_activate_path(anchor, path_name)
    color = @ctx.rng.choice(@opts.fetch("bubble_colors", ["d33aff", "7395c4", "43c2a7", "02ff7f"]).map { |c| Color.from_hex(c) })
    members.each do |id|
      a = @ctx.anim(id)
      @ctx.new_scene(id, "sheen")
      @ctx.add_frame(id, "sheen", a.input_sym, 1, color)
      @ctx.activate_scene(id, "sheen")
    end
    { ids: members, anchor: anchor, radius: radius, low: lowest, landed: false }
  end

  def bubble_move(bubble)
    @ctx.motion_move(bubble[:anchor])
    a = @ctx.anim(bubble[:anchor])
    pts = @ctx.canvas.find_coords_on_circle(a.cur_col, a.cur_row, bubble[:radius], bubble[:ids].length, false)
    bubble[:ids].each_with_index do |id, i|
      next unless pts[i]
      @ctx.motion_set_coordinate(id, pts[i][0], pts[i][1])
      bubble[:landed] = true if pts[i][1] == bubble[:low]
    end
    bubble[:landed] = true if @pop_condition == "anywhere" && @ctx.rng.random < 0.002
    bubble[:ids].each { |id| @ctx.step_animation(id, self) }
  end

  def bubble_pop(bubble)
    a = @ctx.anim(bubble[:anchor])
    pts = @ctx.canvas.find_coords_on_circle(a.cur_col, a.cur_row, bubble[:radius] + 3, bubble[:ids].length, true)
    bubble[:ids].zip(pts).each do |id, point|
      @ctx.motion_new_path(id, "pop_out", 0.3, "out_expo", 0, false)
      @ctx.motion_add_waypoint(id, "pop_out", point[0], point[1])
      @ctx.register_event(id, "path_complete", "pop_out", "path", "final")
    end
    bubble[:ids].each do |id|
      @ctx.activate_scene(id, "pop_1")
      @ctx.motion_activate_path(id, "pop_out")
      @ctx.active_include(id)
    end
  end

  def next_frame
    if @animating.empty? && @ctx.active_empty? && @bubbles.empty?
      return nil
    end
    if !@bubbles.empty? && @steps_since >= @bubble_delay
      b = @bubbles.shift
      b[:ids].each { |id| @ctx.set_visible(id, true) }
      @animating << b
      @steps_since = 0
    end
    @steps_since += 1
    @animating.dup.each do |b|
      if b[:landed]
        bubble_pop(b)
        @animating.delete(b)
      else
        bubble_move(b)
      end
    end
    @ctx.update(self)
    @ctx.frame_string
  end
end

# Synthgrid: extend a generated grid, dissolve input blocks into text, then
# retract the grid. The block dissolves preserve Rust's random symbol/color
# cadence and bounded active-block schedule.
class SynthgridEffect < RemainingEffect
  def self.find_even_gap(dim)
    dimension = dim - 2
    return 0 if dimension <= 0
    candidates = []
    i = dimension
    while i > 4
      candidates << i if (dimension % i) <= 1
      i -= 1
    end
    return 4 if candidates.empty?
    target = dimension.div(5)
    best = candidates[0]
    best_delta = (best - target).abs
    index = 1
    while index < candidates.length
      delta = (candidates[index] - target).abs
      if delta < best_delta
        best = candidates[index]
        best_delta = delta
      end
      index += 1
    end
    best
  end

  def make_line(origin, horizontal, mapping)
    cv = @ctx.canvas
    sym = horizontal ? @opts.fetch("grid_row_symbol", "─") : @opts.fetch("grid_column_symbol", "│")
    coords = if horizontal
      (cv.left..cv.right).map { |col| [col, origin[1]] }
    else
      (cv.bottom...cv.top).map { |row| [origin[0], row] }
    end
    ids = coords.map do |col, row|
      id = @ctx.add_character(sym, 0, 0)
      @ctx.new_scene(id, "grid")
      @ctx.add_frame(id, "grid", sym, 1, mapping.get(col, row))
      @ctx.activate_scene(id, "grid")
      @ctx.anim(id).layer = 2
      @ctx.motion_set_coordinate(id, col, row)
      id
    end
    { direction: horizontal ? :horizontal : :vertical, all: ids, collapsed: ids.dup, extended: [] }
  end

  def build
    cv = @ctx.canvas
    @text_map = gradient(@opts.fetch("text_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"]), @opts.fetch("text_gradient_steps", [12]), @opts.fetch("text_gradient_direction", "vertical"))[1]
    @grid_map = gradient(@opts.fetch("grid_gradient_stops", ["CC00CC", "ffffff"]), @opts.fetch("grid_gradient_steps", [12]), @opts.fetch("grid_gradient_direction", "diagonal"))[1]
    tg = Gradient.build(@opts.fetch("text_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"]).map { |c| Color.from_hex(c) }, @opts.fetch("text_gradient_steps", [12]), false, false)
    @ids = rust_order
    @final_colors = {}
    @ids.each do |id|
      a = @ctx.anim(id)
      @final_colors[id] = a.input_sym == " " ? nil : @text_map.get(a.input_col, a.input_row)
    end

    @lines = [
      make_line([cv.left, cv.bottom], true, @grid_map),
      make_line([cv.left, cv.top], true, @grid_map),
      make_line([cv.left, cv.bottom], false, @grid_map),
      make_line([cv.right, cv.bottom], false, @grid_map)
    ]
    if cv.top > 2 * cv.right
      row_gap = self.class.find_even_gap(cv.top) + 1
      column_gap = row_gap * 2
    else
      column_gap = self.class.find_even_gap(cv.right) + 1
      row_gap = column_gap.div(2)
    end
    row_indexes = []
    column_indexes = []
    row = cv.bottom + row_gap
    while row < cv.top
      if cv.top - row >= 2
        row_indexes << row
        @lines << make_line([cv.left, row], true, @grid_map)
      end
      row += [row_gap, 1].max
    end
    col = cv.left + column_gap
    while col < cv.right
      if cv.right - col >= 2
        column_indexes << col
        @lines << make_line([col, cv.bottom], false, @grid_map)
      end
      col += [column_gap, 1].max
    end
    row_indexes << cv.top + 1
    column_indexes << cv.right + 1
    @blocks = []
    prev_row = 1
    row_indexes.each do |row_bound|
      row_bound += 1 if row_bound == cv.top
      prev_col = 1
      column_indexes.each do |col_bound|
        group = []
        (prev_row...row_bound).each do |r|
          (prev_col...col_bound).each do |c|
            id = cv.char_by_coord(c, r)
            group << id unless id.nil?
          end
        end
        @blocks << group unless group.empty?
        prev_col = col_bound
      end
      prev_row = row_bound
    end
    @blocks.each_with_index do |group, gi|
      group.each do |id|
        a = @ctx.anim(id)
        @ctx.new_scene(id, "dissolve")
        @ctx.rng.randint(15, 30).times do
          sym = @ctx.rng.choice(@opts.fetch("text_generation_symbols", ["░", "▒", "▓"]))
          color = @ctx.rng.choice(tg.spectrum)
          @ctx.add_frame(id, "dissolve", sym, 2, color)
        end
        @ctx.add_frame(id, "dissolve", a.input_sym, 1, @final_colors[id])
        @ctx.activate_scene(id, "dissolve")
        @ctx.register_event(id, "scene_complete", "dissolve", "callback", gi)
      end
    end
    @trackers = Array.new(@blocks.length, 0)
    @group_by_id = {}
    # Dissolve callbacks capture each group's original index. Keep the same
    # index for tracker updates after randomizing the order in which groups
    # are activated; rebuilding this map after shuffle strands active_groups.
    @blocks.each_with_index { |g, i| g.each { |id| @group_by_id[id] = i } }
    @ctx.rng.shuffle(@blocks)
    @phase = :expand
    @max_active = @opts.fetch("max_active_blocks", 0.1).to_f
    @active_groups = 0
    @total_groups = @blocks.length
    @lines.each do |line|
      line[:all].each { |id| @ctx.set_visible(id, false) }
    end
    @ids.each { |id| @ctx.set_visible(id, false) }
  end

  def on_callback(_ctx, id, group)
    @trackers[group] -= 1 if group.is_a?(Integer) && group >= 0 && group < @trackers.length
  end

  def next_frame
    case @phase
    when :expand
      if @lines.all? { |l| l[:collapsed].empty? }
        @phase = :add
      else
        @lines.each do |line|
          n = line[:direction] == :horizontal ? 3 : 1
          n.times do
            id = line[:collapsed].shift
            break if id.nil?
            @ctx.set_visible(id, true)
            line[:extended] << id
          end
        end
      end
    when :add
      if !@blocks.empty? && @active_groups < @total_groups * @max_active
        group = @blocks.shift
        group.each do |id|
          @ctx.set_visible(id, true)
          @ctx.active_include(id)
          @trackers[@group_by_id[id]] += 1
        end
      end
      if @blocks.empty? && @ctx.active_empty? && @active_groups == 0
        @phase = :collapse
      end
    when :collapse
      if @lines.all? { |l| l[:extended].empty? }
        @phase = :done
      else
        @lines.each do |line|
          if line[:collapsed].empty?
            line[:extended].reverse!
          end
          n = line[:direction] == :horizontal ? 3 : 1
          n.times do
            id = line[:extended].shift
            break if id.nil?
            @ctx.set_visible(id, false)
            line[:collapsed] << id
          end
        end
      end
    when :done
      return nil
    end
    @ctx.update(self)
    @active_groups = @trackers.count { |n| n != 0 }
    @ctx.frame_string
  end
end

# Blackhole: form a colored ring, draw text into the singularity, collapse it,
# then launch the characters back out before they cool at home.
class BlackholeEffect < RemainingEffect
  def build
    opts = @opts
    @mapping = gradient(opts.fetch("final_gradient_stops", ["8A008A", "00D1FF", "ffffff"]), opts.fetch("final_gradient_steps", [9]), opts.fetch("final_gradient_direction", "diagonal"))[1]
    cv = @ctx.canvas
    @center = [cv.center_column, cv.center_row]
    @radius = [[PyCompat.round_half_even(cv.right * 0.3), PyCompat.round_half_even(cv.top * 0.20)].min, 3].max
    @ids = rust_order
    @final_map = {}
    @ids.each do |id|
      a=@ctx.anim(id); @final_map[id]=@mapping.get(a.input_col,a.input_row)
    end
    blackhole_color = Color.from_hex(opts.fetch("blackhole_color", "ffffff"))
    available = @ids.dup
    @ring=[]
    while @ring.length < @radius * 3 && !available.empty?
      @ring << available.delete_at(@ctx.rng.randrange(0, available.length))
    end
    @others = @ids.reject { |id| @ring.include?(id) }
    pts = cv.find_coords_on_circle(@center[0], @center[1], @radius, @ring.length, true)
    @ring.each_with_index do |id, i|
      @ctx.motion_new_path(id, "blackhole", 0.7, "in_out_sine", 0, false)
      @ctx.motion_add_waypoint(id, "blackhole", pts[i][0], pts[i][1])
      @ctx.new_scene(id, "blackhole")
      @ctx.add_frame(id, "blackhole", "*", 1, blackhole_color)
      @ctx.register_event(id, "path_activated", "blackhole", "layer", 1)
      rotated = pts[i..-1] + pts[0...i]
      @ctx.motion_new_path(id, "blackhole_rotation", 0.45, nil, 0, true)
      rotated.each { |c,r| @ctx.motion_add_waypoint(id, "blackhole_rotation", c, r) }
    end
    star_symbols = ["*", "'", "`", "¤", "•", "°", "·"]
    sf = Gradient.with_steps([[74,74,77],[255,255,255]],6,false).spectrum
    gradient_map = sf.map { |color| Gradient.with_steps([color,[0,0,0]],10,false).spectrum }
    @awaiting_consume=[]
    @ids.each do |id|
      sym = @ctx.rng.choice(star_symbols)
      ci = @ctx.rng.choice_index(sf.length)
      star_color = sf[ci]
      @ctx.new_scene(id, "star")
      @ctx.add_frame(id, "star", sym, 1, star_color)
      @ctx.activate_scene(id, "star")
      @ctx.set_visible(id, true)
      next if @ring.include?(id)
      a=@ctx.anim(id)
      start = [@ctx.rng.randint(cv.left,cv.right), @ctx.rng.randint(cv.bottom,cv.top)]
      speed = @ctx.rng.uniform(0.17,0.30)
      @ctx.motion_set_coordinate(id,start[0],start[1])
      @ctx.motion_new_path(id,"singularity",speed,"in_expo",0,false)
      @ctx.motion_add_waypoint(id,"singularity",@center[0],@center[1])
      @ctx.new_scene_synced(id,"consumed","distance")
      gradient_map[ci].each { |c| @ctx.add_frame(id,"consumed",sym,1,c) }
      @ctx.add_frame(id,"consumed"," ",1,nil)
      @ctx.register_event(id,"path_activated","singularity","layer",2)
      @ctx.register_event(id,"path_activated","singularity","scene","consumed")
      @awaiting_consume << id
    end
    @ctx.rng.shuffle(@awaiting_consume)
    @form_pending=@ring.dup
    @formation_delay=[100 / [@ring.length,1].max,6].max
    @delay=@formation_delay
    @phase=:form
  end

  def activate_collapse
    pts=@ctx.canvas.find_coords_on_circle(@center[0],@center[1],@radius+3,@ring.length,true)
    unstable=["◦","◎","◉","●","◉","◎","◦"]
    star_colors=@opts.fetch("star_colors",["ffcc0d","ff7326","ff194d","bf2669","702a8c","049dbf"]).map{|x|Color.from_hex(x)}
    first=true
    @ring.each_with_index do |id,i|
      p1=@ctx.motion_new_path(id,"",0.2,"in_expo",0,false)
      @ctx.motion_add_waypoint(id,p1,pts[i][0],pts[i][1])
      p2=@ctx.motion_new_path(id,"",0.3,"in_expo",0,false)
      @ctx.motion_add_waypoint(id,p2,@center[0],@center[1])
      @ctx.register_event(id,"path_complete",p1,"path",p2)
      if first
        point=@ctx.motion_new_path(id,"",0.01,"linear",0,false) rescue nil
        # The point is the first ring character and only animates after collapse.
        scene="point"
        @ctx.new_scene(id,scene)
        3.times { unstable.each { |sym| @ctx.add_frame(id,scene,sym,3,@ctx.rng.choice(star_colors)) } }
        @ctx.register_event(id,"path_complete",p2,"scene",scene)
        @ctx.register_event(id,"path_complete",p2,"layer",3)
        first=false
      end
      @ctx.motion_activate_path(id,p1)
      @ctx.active_include(id)
    end
  end

  def explode_singularity
    colors=["ffcc0d","ff7326","ff194d","bf2669","702a8c","049dbf"].map{|x|Color.from_hex(x)}
    @ids.each do |id|
      a=@ctx.anim(id); sym=a.input_sym; final=@final_map[id]
      nearby=@ctx.canvas.find_coords_on_circle(a.input_col,a.input_row,3,5,true)
      near=nearby[@ctx.rng.randrange(0,5)]
      ns=@ctx.rng.randint(3,4)/10.0
      p1=@ctx.motion_new_path(id,"",ns,"out_expo",0,false)
      @ctx.motion_add_waypoint(id,p1,near[0],near[1])
      ins=@ctx.rng.randint(4,6)/100.0
      p2=@ctx.motion_new_path(id,"",ins,"in_cubic",0,false)
      @ctx.motion_add_waypoint(id,p2,a.input_col,a.input_row)
      color=@ctx.rng.choice(colors)
      scene="explode"; @ctx.new_scene(id,scene); @ctx.add_frame(id,scene,sym,1,color)
      cool="cooldown"; @ctx.new_scene(id,cool)
      Gradient.with_steps([color,final],10,false).spectrum.each{|c|@ctx.add_frame(id,cool,sym,20,c)}
      @ctx.register_event(id,"path_complete",p1,"path",p2)
      @ctx.register_event(id,"path_complete",p1,"scene",cool)
      @ctx.activate_scene(id,scene)
      @ctx.motion_activate_path(id,p1)
      @ctx.active_include(id)
    end
  end

  def next_frame
    case @phase
    when :form
      if !@form_pending.empty?
        if @delay.zero?
          id=@form_pending.shift
          @ctx.motion_activate_path(id,"blackhole")
          @ctx.activate_scene(id,"blackhole")
          @ctx.active_include(id)
          @delay=@formation_delay
        else
          @delay-=1
        end
      elsif @ctx.active_empty?
        @ring.each{|id|@ctx.motion_activate_path(id,"blackhole_rotation");@ctx.active_include(id)}
        @phase=:consume
      end
    when :consume
      if !@awaiting_consume.empty?
        @awaiting_consume.each{|id|@ctx.motion_activate_path(id,"singularity");@ctx.active_include(id)}
        @awaiting_consume=[]
      elsif @ctx.active.all?{|id|@ring.include?(id)}
        @phase=:collapse
      end
    when :collapse
      activate_collapse
      @phase=:explode
    when :explode
      if @ring.all?{|id|@ctx.anim(id).active_path.nil? && @ctx.anim(id).active.nil?}
        explode_singularity
        @phase=:complete
      end
    when :complete
      return nil if @ctx.active_empty?
    end
    @ctx.update(self)
    @ctx.frame_string
  end
end

# VHS tapeend

# VHS tape: RGB scanline offsets and snow/noise run for a bounded glitch
# window, then a static sweep restores each line to the final gradient.
class VhstapeEffect < RemainingEffect
  def build
    @mapping = gradient(@opts.fetch("final_gradient_stops", ["ab48ff", "e7b2b2", "fffebd"]), @opts.fetch("final_gradient_steps", [12]), @opts.fetch("final_gradient_direction", "vertical"))[1]
    @ids = rust_order
    @line_colors = @opts.fetch("glitch_line_colors", ["ffffff", "ff0000", "00ff00", "0000ff", "ffffff"]).map { |c| Color.from_hex(c) }
    @wave_colors = @opts.fetch("glitch_wave_colors", ["ffffff", "ff0000", "00ff00", "0000ff", "ffffff"]).map { |c| Color.from_hex(c) }
    @noise_colors = @opts.fetch("noise_colors", ["1e1e1f", "3c3b3d", "6d6c70", "a2a1a6", "cbc9cf", "ffffff"]).map { |c| Color.from_hex(c) }
    @stable_colors = {}
    @final_colors = {}
    @ids.each do |id|
      a = @ctx.anim(id)
      final = @mapping.get(a.input_col, a.input_row)
      @stable_colors[id] = final
      @final_colors[id] = final
    end
    @lines = []
    @ctx.canvas.grouped_ids("row_bottom_to_top").each do |line_ids|
      build_vhs_line(line_ids)
      @lines << { characters: line_ids }
    end
    @ids.each do |id|
      @ctx.set_visible(id, true)
      @ctx.activate_scene(id, "base")
    end
    @wave_top = nil
    @wave_lines = []
    @glitch_lines = []
    @elapsed = 0
    @duration = @opts.fetch("total_glitch_time", 600).to_i
    @line_chance = @opts.fetch("glitch_line_chance", 0.05).to_f
    @noise_chance = @opts.fetch("noise_chance", 0.004).to_f
    @phase = :glitching
    @to_redraw = (0...@lines.length).to_a
    @redrawing = false
  end

  def build_vhs_line(ids)
    offset = @ctx.rng.randint(4, 25)
    direction = @ctx.rng.choice([-1, 1])
    hold = @ctx.rng.randint(1, 50)
    ids.each do |id|
      a = @ctx.anim(id)
      sym = a.input_sym
      final = @final_colors[id]
      stable = @stable_colors[id]
      @ctx.motion_new_path(id, "glitch", 2.0, nil, hold, false)
      @ctx.motion_add_waypoint(id, "glitch", a.input_col + offset * direction, a.input_row)
      @ctx.motion_new_path(id, "restore", 2.0, nil, 0, false)
      @ctx.motion_add_waypoint(id, "restore", a.input_col, a.input_row)
      @ctx.motion_new_path(id, "glitch_wave_mid", 2.0, nil, 0, false)
      @ctx.motion_add_waypoint(id, "glitch_wave_mid", a.input_col + 8, a.input_row)
      @ctx.motion_new_path(id, "glitch_wave_end", 2.0, nil, 0, false)
      @ctx.motion_add_waypoint(id, "glitch_wave_end", a.input_col + 14, a.input_row)
      @ctx.new_scene(id, "base")
      @ctx.add_frame(id, "base", sym, 1, stable)
      @ctx.new_scene_synced(id, "rgb_glitch_fwd", "step")
      color_frames(id, "rgb_glitch_fwd", sym, @line_colors, 1)
      @ctx.new_scene_synced(id, "rgb_glitch_bwd", "step")
      color_frames(id, "rgb_glitch_bwd", sym, @line_colors.reverse, 1)
      @ctx.new_scene(id, "snow")
      25.times do
        @ctx.add_frame(id, "snow", @ctx.rng.choice(["#", "*", ".", ":"]), 2, @ctx.rng.choice(@noise_colors))
      end
      @ctx.add_frame(id, "snow", sym, 1, stable)
      @ctx.new_scene(id, "final_snow")
      30.times do
        @ctx.add_frame(id, "final_snow", @ctx.rng.choice(["#", "*", ".", ":"]), 2, @ctx.rng.choice(@noise_colors))
      end
      @ctx.new_scene(id, "final_redraw")
      @ctx.add_frame(id, "final_redraw", "█", 6, Color.from_hex("ffffff"))
      @ctx.add_frame(id, "final_redraw", sym, 1, final)
      @ctx.register_event(id, "path_complete", "glitch", "path", "restore")
      @ctx.register_event(id, "path_activated", "glitch", "scene", "rgb_glitch_fwd")
      @ctx.register_event(id, "path_activated", "restore", "scene", "rgb_glitch_bwd")
      @ctx.register_event(id, "path_activated", "glitch_wave_mid", "scene", "rgb_glitch_fwd")
      @ctx.register_event(id, "path_activated", "glitch_wave_end", "scene", "rgb_glitch_fwd")
      @ctx.register_event(id, "scene_complete", "rgb_glitch_bwd", "scene", "base")
    end
  end

  def vhs_line_glitch(idx, final = false)
    @lines[idx][:characters].each do |id|
      if final
        @ctx.anim(id).paths["glitch"].hold_left = 0
        @ctx.anim(id).paths["glitch"].hold = 0
        @ctx.anim(id).paths["restore"].hold_left = 0
        @ctx.anim(id).paths["restore"].hold = 0
      end
      @ctx.anim(id).paths["glitch"].speed = 40.0 / @ctx.rng.randint(20, 40)
      @ctx.anim(id).paths["restore"].speed = 40.0 / @ctx.rng.randint(20, 40)
      @ctx.motion_activate_path(id, "glitch")
    end
  end

  def vhs_restore_line(idx)
    @lines[idx][:characters].each do |id|
      @ctx.anim(id).paths["restore"].speed = 40.0 / @ctx.rng.randint(20, 40)
      @ctx.motion_activate_path(id, "restore")
    end
  end

  def vhs_insert_line(idx)
    @lines[idx][:characters].each { |id| @ctx.active_include(id) }
  end

  def vhs_line_complete?(idx)
    @lines[idx][:characters].all? { |id| @ctx.anim(id).active_path.nil? }
  end

  def vhs_glitch_wave
    if @wave_top.nil? || @wave_top == 0
      return if @ctx.canvas.text_height < 3
      lower = [3, PyCompat.round_half_even(@ctx.canvas.text_height * 0.5)].max
      @wave_top = @ctx.canvas.text_bottom + @ctx.rng.randint(lower, @ctx.canvas.text_height)
    end
    if @wave_lines.all? { |idx| vhs_line_complete?(idx) }
      unless @wave_lines.empty?
        top_delta = @ctx.rng.random < 0.3 ? (@ctx.rng.random < 0.3 ? 1 : -1) : 0
        @wave_top = [[@wave_top + top_delta, 2].max, @ctx.canvas.text_top].min
      end
      next_lines = []
      (@wave_top - 2..@wave_top).each do |row|
        idx = row - (@ctx.canvas.text_bottom - 1)
        next_lines << idx if idx >= 0 && idx < @lines.length
      end
      old = @wave_lines
      old.each do |idx|
        unless next_lines.include?(idx)
          vhs_restore_line(idx)
          vhs_insert_line(idx)
        end
      end
      @wave_lines = next_lines
      if @wave_top < @ctx.canvas.text_bottom + 2
        @wave_lines.each do |idx|
          vhs_restore_line(idx)
          vhs_insert_line(idx)
        end
        @wave_lines = []
        @wave_top = nil
      else
        ["glitch_wave_mid", "glitch_wave_end", "glitch_wave_mid"].each_with_index do |path, i|
          idx = @wave_lines[i]
          next if idx.nil?
          @lines[idx][:characters].each { |id| @ctx.motion_activate_path(id, path) }
          vhs_insert_line(idx)
        end
      end
    end
  end

  def next_frame
    return nil if @phase == :complete && @ctx.active_empty?
    case @phase
    when :glitching
      vhs_glitch_wave if @wave_lines.empty? || @wave_lines.all? { |idx| vhs_line_complete?(idx) }
      @glitch_lines.reject! { |idx| vhs_line_complete?(idx) }
      if @ctx.rng.random < @line_chance && @glitch_lines.length < 3
        idx = @ctx.rng.choice_index(@lines.length)
        unless @wave_lines.include?(idx) || @glitch_lines.include?(idx)
          hold = @ctx.rng.randint(20, 75)
          @lines[idx][:characters].each { |id| @ctx.anim(id).paths["glitch"].hold_left = hold; @ctx.anim(id).paths["glitch"].hold = hold }
          @glitch_lines << idx
          vhs_line_glitch(idx)
          vhs_insert_line(idx)
        end
      end
      if @ctx.rng.random < @noise_chance
        @lines.each_with_index do |line, idx|
          line[:characters].each { |id| @ctx.activate_scene(id, "snow") }
          vhs_insert_line(idx) unless @wave_lines.include?(idx) || @glitch_lines.include?(idx)
        end
      end
      @elapsed += 1
      if @elapsed >= @duration
        @wave_lines.each { |idx| vhs_restore_line(idx) }
        @glitch_lines.each { |idx| vhs_restore_line(idx) }
        @phase = :noise
      end
    when :noise
      if @ctx.active_empty?
        @ids.each { |id| @ctx.activate_scene(id, "final_snow"); @ctx.active_include(id) }
        @phase = :redraw
      end
    when :redraw
      if @redrawing || @ctx.active_empty?
        @redrawing = true
        idx = @to_redraw.pop
        if idx.nil?
          @phase = :complete
        else
          @lines[idx][:characters].each { |id| @ctx.activate_scene(id, "final_redraw"); @ctx.active_include(id) }
        end
      end
    end
    draw_tick
  end
end

# Thunderstorm: animated rain, timed lightning flashes, glowing text cooldown,
# and a final settled gradient. The storm duration is configurable in seconds.
class ThunderstormEffect < RemainingEffect
  def build
    @rain_symbols = @opts.fetch("raindrop_symbols", ["\\", ".", ","])
    @spark_symbols = @opts.fetch("spark_symbols", ["*", ".", "'"])
    @spark_glow_time = @opts.fetch("spark_glow_time", 18).to_i
    @rain_pool = ParticlePool.new(@rain_symbols, nil, [0, 0])
    @rain_pool.preallocate(@ctx, 50)
    @rain_pool.particles.each { |id| init_rain(id) }
    @spark_pool = ParticlePool.new(@spark_symbols, 2000, [0, 0])
    @spark_gradient = Gradient.with_steps([Color.from_hex(@opts.fetch("spark_glow_color", "ff4d00")), [0, 0, 0]], 7, false).spectrum
    @spark_pool.preallocate(@ctx, 200)
    @spark_pool.particles.each { |id| init_spark(id) }
    @storm_start = @ctx.now_wall
    @lightning = Color.from_hex(@opts.fetch("lightning_color", "68A3E8"))
    @glow_text = Color.from_hex(@opts.fetch("glowing_text_color", "EF5411"))
    @text_glow_time = @opts.fetch("text_glow_time", 6).to_i
    @spark_glow_time = @opts.fetch("spark_glow_time", 18).to_i
    @storm_time = @opts.fetch("storm_time", 12).to_i
    @mapping = gradient(@opts.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"]), @opts.fetch("final_gradient_steps", [12]), @opts.fetch("final_gradient_direction", "vertical"))[1]
    @strike_available = Array.new(200) { @ctx.add_character("|", 1, 1) }
    @strike_pending = []
    @strike_active = []
    @pending_glow = []
    @strike_progress_delay = 0
    @strike_in_progress = false
    @strike_branch_chance = 0.05
    @rain_delay = 0
    @phase = :pre_storm
    @ids = rust_order
    @ids.each { |id| build_storm_scenes(id) }
    @ctx.register_event(@ids[0], "scene_complete", "fade", "callback", :fade_complete) unless @ids.empty?
  end

  def init_rain(id)
    a = @ctx.anim(id)
    a.layer = 1
    @ctx.set_appearance(id, a.input_sym, Color.from_hex("aaaaff"))
  end

  def init_spark(id)
    a = @ctx.anim(id)
    a.layer = 2
    @ctx.new_scene_eased(id, "glow", "in_circ")
    color_frames(id, "glow", a.input_sym, @spark_gradient, @spark_glow_time)
  end

  def build_storm_scenes(id)
    a = @ctx.anim(id)
    final = @mapping.get(a.input_col, a.input_row)
    storm = Color.adjust_brightness(final, 0.5)
    glow = Gradient.with_steps([@glow_text, storm], 7, false).spectrum
    @ctx.new_scene(id, "glow")
    color_frames(id, "glow", a.input_sym, glow, @text_glow_time)
    @ctx.new_scene(id, "fade")
    color_frames(id, "fade", a.input_sym, Gradient.with_steps([final, storm], 7, false).spectrum, 12)
    @ctx.new_scene(id, "unfade")
    color_frames(id, "unfade", a.input_sym, Gradient.with_steps([final, storm], 7, false).spectrum.reverse, 12)
    @ctx.new_scene(id, "flash")
    @flash_frames ||= {}
    @flash_frames[id] = Gradient.with_steps([storm, Color.adjust_brightness(final, 1.7)], 7, true).spectrum
    color_frames(id, "flash", a.input_sym, @flash_frames[id], 6)
    @ctx.set_visible(id, true)
  end

  def acquire_particle(pool, initializer)
    id = pool.acquire(@ctx)
    if id.nil?
      id = @ctx.add_character(@ctx.rng.choice(pool.instance_variable_get(:@symbols)), 0, 0)
      pool.particles << id
      initializer.call(id)
    end
    @ctx.anim(id).paths.clear
    @ctx.anim(id).active_path = nil
    @ctx.anim(id).active = nil
    @ctx.clear_char_events(id)
    id
  end

  def setup_rain(id)
    a = @ctx.anim(id)
    speed = @ctx.rng.uniform(0.5, 1.5)
    cv = @ctx.canvas
    pname = @ctx.motion_new_path(id, "", speed, nil, 0, false)
    @ctx.motion_add_waypoint(id, pname, a.cur_col + cv.top + 1, cv.bottom - 1)
    @ctx.register_event(id, "path_complete", pname, "callback", :reclaim_rain)
    @ctx.motion_activate_path(id, pname)
  end

  def emit_rain
    if @rain_delay != 0
      @rain_delay -= 1
      return
    end
    count = @ctx.rng.randint(1, 6)
    count.times do
      spawn_column = @ctx.rng.randint(1 - @ctx.canvas.top, @ctx.canvas.right)
      id = acquire_particle(@rain_pool, method(:init_rain))
      @ctx.motion_set_coordinate(id, spawn_column - 1, @ctx.canvas.top + 1)
      setup_rain(id)
      @ctx.set_visible(id, true)
      @ctx.active_include(id)
    end
    @rain_delay = @ctx.rng.randint(1, 7)
  end

  def get_strike_char
    @strike_available.concat(Array.new(20) { @ctx.add_character("|", 1, 1) }) if @strike_available.empty?
    id = @strike_available.pop
    a = @ctx.anim(id)
    a.layer = 1
    a.scenes.clear
    a.active = nil
    a.paths.clear
    a.active_path = nil
    @ctx.clear_char_events(id)
    id
  end

  def setup_strike(branch = nil)
    if branch
      column = @ctx.anim(branch).cur_col
      row = @ctx.anim(branch).cur_row
    else
      column = @ctx.rng.randint(1, @ctx.canvas.right)
      row = @ctx.canvas.top
    end
    while row >= @ctx.canvas.bottom
      symbol = if branch
        delta = @ctx.rng.choice([-1, 1])
        column += delta
        delta == 1 ? "\\" : "/"
      else
        @ctx.rng.choice(["\\", "/", "|"])
      end
      id = get_strike_char
      @ctx.motion_set_coordinate(id, column, row)
      @ctx.set_appearance(id, symbol, @lightning)
      @strike_pending << id
      row -= 1
      column += 1 if symbol == "\\"
      column -= 1 if symbol == "/"
      should_branch = @ctx.rng.random < @strike_branch_chance
      if should_branch && branch.nil?
        @strike_branch_chance -= 0.01
        setup_strike(id)
      end
      branch = nil
    end
    @strike_branch_chance = 0.05
  end

  def start_lightning
    setup_strike
    strikes = @strike_pending.dup
    @flash_ease = [0.0, 1.6, 1.0, @ctx.rng.uniform(-0.6, 0.4)]
    flash = Gradient.with_steps([@lightning, Color.adjust_brightness(@lightning, 1.7)], 7, true).spectrum
    fade = Gradient.with_steps([@lightning, [0, 0, 0]], 6, false).spectrum
    strikes.each do |id|
      sym = @ctx.anim(id).cur_sym
      @ctx.new_scene_eased(id, "strike_flash", @flash_ease)
      color_frames(id, "strike_flash", sym, flash, 6)
      @ctx.new_scene(id, "strike_fade")
      color_frames(id, "strike_fade", sym, fade, 2)
      @ctx.register_event(id, "scene_complete", "strike_flash", "scene", "strike_fade")
      @ctx.register_event(id, "scene_complete", "strike_fade", "callback", :hide_strike)
      @ctx.register_event(id, "scene_complete", "strike_fade", "callback", :make_glow)
      @ctx.register_event(id, "scene_complete", "strike_fade", "callback", :return_strike)
    end
    @ids.each do |id|
      a = @ctx.anim(id)
      scene = Scene.new("flash", @flash_ease)
      @flash_frames[id].each { |color| scene.add_frame(a.input_sym, color, 6) }
      a.scenes["flash"] = scene
    end
  end

  def emit_spark(origin)
    id = acquire_particle(@spark_pool, method(:init_spark))
    @ctx.motion_set_coordinate(id, origin[0], origin[1])
    speed = @ctx.rng.uniform(0.1, 0.25)
    pname = @ctx.motion_new_path(id, "", speed, "out_quint", 30, false)
    offset = @ctx.rng.randint(4, 20) * @ctx.rng.choice([1, -1])
    tx = origin[0] + offset
    ty = @ctx.canvas.bottom
    control_col = origin[0] - ((origin[0] - tx).div(2))
    control_row = @ctx.rng.randint(1, @ctx.canvas.top)
    @ctx.motion_add_waypoint(id, pname, tx, ty, [[control_col, control_row]])
    @ctx.register_event(id, "scene_complete", "glow", "callback", :reclaim_spark)
    @ctx.activate_scene(id, "glow")
    @ctx.motion_activate_path(id, pname)
    @ctx.set_visible(id, true)
    @ctx.active_include(id)
  end

  def step_strike
    if @strike_progress_delay != 0
      @strike_progress_delay -= 1
      return
    end
    return if @strike_pending.empty?
    batch = @ctx.rng.randint(1, 3)
    batch.times do
      break if @strike_pending.empty?
      id = @strike_pending.shift
      @strike_active << id
      @ctx.set_visible(id, true)
      @strike_progress_delay = 1
      if @strike_pending.empty?
         @ctx.rng.randint(12, 18).times { emit_spark([@ctx.anim(id).cur_col, @ctx.anim(id).cur_row]) }
        @ctx.register_event(id, "scene_complete", "strike_fade", "callback", :strike_complete)
        strikes = @strike_active
        @strike_active = []
        strikes.each { |sid| @ctx.activate_scene(sid, "strike_flash"); @ctx.active_include(sid) }
        @ids.each do |cid|
          @ctx.activate_scene(cid, "flash")
          @ctx.active_include(cid)
        end
      end
    end
  end

  def on_callback(_ctx, id, action)
    case action
    when :fade_complete
      @phase = :storm
      @storm_start = @ctx.now_wall
    when :hide_strike
      @ctx.set_visible(id, false)
    when :make_glow
      coord = [@ctx.anim(id).cur_col, @ctx.anim(id).cur_row]
      home = @ctx.canvas.char_by_coord(coord[0], coord[1])
      if !home.nil? && @ctx.anim(home).visible
        @ctx.activate_scene(home, "glow")
        @pending_glow << home
      end
    when :return_strike
      @strike_available << id
    when :strike_complete
      @strike_in_progress = false
    when :reclaim_rain
      @rain_pool.reclaim(@ctx, id, true, true)
    when :reclaim_spark
      @spark_pool.reclaim(@ctx, id, true, true)
    end
  end

  def next_frame
    return nil if @ctx.active_empty? && @phase == :complete
    case @phase
    when :pre_storm
      @ids.each { |id| @ctx.activate_scene(id, "fade"); @ctx.active_include(id) }
      @phase = :waiting
    when :storm
      emit_rain
      if !@strike_in_progress && @ctx.rng.random < 0.008
        @strike_in_progress = true
        start_lightning
      end
      step_strike if @strike_in_progress
      @pending_glow.each { |id| @ctx.active_include(id) }
      @pending_glow.clear
      if @ctx.now_wall - @storm_start >= @storm_time && !@strike_in_progress
        @ids.each { |id| @ctx.activate_scene(id, "unfade"); @ctx.active_include(id) }
        @phase = :complete
      end
    when :waiting, :complete
      # The pre-storm and final gradients advance through the active scenes.
    end
    draw_tick
  end
end
