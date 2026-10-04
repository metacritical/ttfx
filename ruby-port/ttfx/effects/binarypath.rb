# Faithful binarypath (ttfx src/effects/binarypath.rs, old-engine semantics).
#
# Each character's code point becomes 8 binary digits that travel manhattan
# paths from outside the canvas home; on arrival the source collapses in
# through white, then a diagonal wipe brightens everything to final colors.
class BinarypathEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    stop_hex = o.fetch("final_gradient_stops", ["00d500", "007500"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "radial")
    bin_hex = o.fetch("binary_colors", ["044E29", "157e38", "45bf55", "95ed87"])
    @speed = o.fetch("movement_speed", 1.0)
    @active_ratio = o.fetch("active_binary_groups", 0.08)
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @binary_colors = bin_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @active_reps = []
    @final_map = {}
    @phase = "travel"
    @wipe_groups = []
    @max_active = 1
    @complete = false
    @last_provided = false
  end

  def travel_complete?(rep)
    rep[1].each do |bid|
      a = @ctx.anim(bid)
      return false unless a.cur_col == rep[4][0] && a.cur_row == rep[4][1]
    end
    true
  end

  def build
    @wipe_groups = @ctx.canvas.grouped_ids("diagonal_top_right_to_bottom_left")
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      @final_map[id] = mapping.get(a.input_col, a.input_row)
    end
    order.each do |id|
      a = @ctx.anim(id)
      bits = a.input_sym.ord.to_s(2).rjust(8, "0")
      bins = []
      pend = []
      bits.each_char do |b|
        bid = @ctx.add_character(b, 0, 0)
        bins.push(bid)
        pend.push(bid)
      end
      @pending.push([id, bins, pend, false, [a.input_col, a.input_row]])
    end
    @pending.each do |rep|
      icol = rep[4][0]
      irow = rep[4][1]
      sc = @ctx.canvas.random_coord(@ctx.rng, true, false)
      coords = [[sc[0], sc[1]]]
      orient = @ctx.rng.choice(["col", "row"])
      nxt = [sc[0], sc[1]]
      while coords[coords.length - 1] != [icol, irow]
        last = coords[coords.length - 1]
        cdir = last[0] > icol ? -1 : (last[0] == icol ? 0 : 1)
        rdir = last[1] > irow ? -1 : (last[1] == irow ? 0 : 1)
        maxc = (last[0] - icol).abs
        maxr = (last[1] - irow).abs
        if orient == "col" && maxr > 0
          lim = maxr
          cap = (@ctx.canvas.right.to_f * 0.2).to_i
          cap = 10 if cap < 10
          lim = cap if lim > cap
          nxt = [last[0], last[1] + @ctx.rng.randint(1, lim) * rdir]
          orient = "row"
        elsif orient == "row" && maxc > 0
          lim = maxc
          lim = 4 if lim > 4
          nxt = [last[0] + @ctx.rng.randint(1, lim) * cdir, last[1]]
          orient = "col"
        else
          nxt = [icol, irow]
        end
        coords.push([nxt[0], nxt[1]])
      end
      coords.push([nxt[0], nxt[1]])
      coords.push([icol, irow])
      rep[1].each do |bid|
        @ctx.motion_set_coordinate(bid, coords[0][0], coords[0][1])
        pname = @ctx.motion_new_path(bid, "", @speed, nil, 0, false)
        coords.each do |c|
          @ctx.motion_add_waypoint(bid, pname, c[0], c[1])
        end
        @ctx.motion_activate_path(bid, pname)
        @ctx.anim(bid).layer = 1
        color = @ctx.rng.choice(@binary_colors)
        @ctx.new_scene(bid, "color")
        @ctx.add_frame(bid, "color", @ctx.anim(bid).input_sym, 1, color)
        @ctx.activate_scene(bid, "color")
      end
    end
    order.each do |id|
      a = @ctx.anim(id)
      final = @final_map[id]
      dim = Color.adjust_brightness(final, 0.5)
      @ctx.new_scene_eased(id, "collapse_scn", "in_quad")
      cg = Gradient.with_steps([[255, 255, 255], dim], 7, false)
      pairs = cg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "collapse_scn", [a.input_sym], 3, pairs)
      @ctx.new_scene(id, "brighten_scn")
      bg = Gradient.with_steps([dim, final], 10, false)
      bpairs = bg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "brighten_scn", [a.input_sym], 2, bpairs)
    end
    @max_active = (@active_ratio * @pending.length.to_f).to_i
    @max_active = 1 if @max_active < 1
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    if !@complete || !@ctx.active_empty?
      if @phase == "travel"
        while @active_reps.length < @max_active && !@pending.empty?
          idx = @ctx.rng.randrange(0, @pending.length)
          rep = @pending.delete_at(idx)
          rep[3] = true
          @active_reps.push(rep)
        end
        unless @active_reps.empty?
          @active_reps.each do |rep|
            if !rep[2].empty?
              nid = rep[2].shift
              @ctx.active_include(nid)
              @ctx.set_visible(nid, true)
            elsif travel_complete?(rep)
              rep[1].each { |bid| @ctx.set_visible(bid, false) }
              rep[3] = false
              @ctx.set_visible(rep[0], true)
              @ctx.activate_scene(rep[0], "collapse_scn")
              @ctx.active_include(rep[0])
            end
          end
          @active_reps = @active_reps.select { |rep| rep[3] }
        end
        if @ctx.active_empty?
          @phase = "wipe"
        end
      end
      if @phase == "wipe"
        2.times do
          if !@wipe_groups.empty?
            g = @wipe_groups.shift
            g.each do |id|
              @ctx.activate_scene(id, "brighten_scn")
              @ctx.set_visible(id, true)
              @ctx.active_include(id)
            end
          else
            @complete = true
          end
        end
      end
      @ctx.update
      return @ctx.frame_string
    end
    unless @last_provided
      @last_provided = true
      return @ctx.frame_string
    end
    nil
  end
end
