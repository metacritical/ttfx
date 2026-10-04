# Faithful burn (ttfx src/effects/burn.rs, old-engine semantics).
#
# A Prim's-ordered ignition front burns each character through fire colors
# into its final gradient; burning characters puff recycled smoke particles
# that rise and fade. Particle emission/reclaim runs through callbacks.
class BurnEffect
  BURN_ORDER = ["'", ".", "\u2596", "\u2599", "\u2588", "\u259c", "\u2580", "\u259d", "."].freeze
  SMOKE_SYMBOLS = [".", ",", "'", "`", "#", "*"].freeze

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @starting = Color.from_hex(o.fetch("starting_color", "837373"))
    burn_hex = o.fetch("burn_colors", ["ffffff", "fff75d", "fe650d", "8A003C", "510100"])
    @smoke_chance = o.fetch("smoke_chance", 0.5)
    stop_hex = o.fetch("final_gradient_stops", ["00c3ff", "ffff1c"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @burn_stops = burn_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @final_map = {}
    @link_order = []
    @pool = nil
  end

  def init_smoke(id)
    g = Gradient.with_steps([[80, 79, 79], [199, 199, 199]], 9, false)
    @ctx.new_scene(id, "smoke")
    g.spectrum.each do |c|
      @ctx.add_frame(id, "smoke", @ctx.anim(id).input_sym, 10, c)
    end
    @ctx.anim(id).layer = 2
  end

  def emit_smoke(origin_col, origin_row)
    return if @ctx.rng.random > @smoke_chance
    id = @pool.acquire(@ctx)
    return if id.nil?
    @ctx.motion_set_coordinate(id, origin_col, origin_row)
    pname = @ctx.motion_new_path(id, "", 0.5, nil, 0, false)
    top = @ctx.canvas.top
    @ctx.motion_add_waypoint(id, pname, @ctx.rng.randint(origin_col - 4, origin_col + 4), top + 1)
    @ctx.motion_activate_path(id, pname)
    @ctx.activate_scene(id, "smoke")
    @ctx.register_event(id, "scene_complete", "smoke", "callback", 1)
    @ctx.set_visible(id, true)
    @ctx.active_include(id)
  end

  def on_callback(ctx, id, cbid)
    if cbid == 0
      a = ctx.anim(id)
      emit_smoke(a.input_col, a.input_row)
    elsif cbid == 1
      @pool.reclaim(ctx, id, true, true)
    end
  end

  def build
    algo = PrimsSimple.new(@ctx, nil, true)
    @pool = ParticlePool.new(SMOKE_SYMBOLS, 2000, [0, 0])
    @pool.preallocate(@ctx, 2000)
    @pool.particles.each do |pid|
      init_smoke(pid)
    end
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      @final_map[id] = mapping.get(a.input_col, a.input_row)
    end
    fire = Gradient.with_steps(@burn_stops, 10, false)
    until algo.complete
      algo.step(@ctx)
    end
    order.each do |id|
      a = @ctx.anim(id)
      @ctx.set_visible(id, true)
      @ctx.set_appearance(id, a.input_sym, @starting)
      @ctx.new_scene(id, "burn")
      pairs = fire.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "burn", BURN_ORDER, 4, pairs)
      @ctx.new_scene(id, "final_#{id}")
      final = @final_map[id]
      fg = Gradient.with_steps([fire.spectrum[fire.spectrum.length - 1], final], 8, false)
      fpairs = fg.spectrum.map { |c| [c, nil] }
      fpairs.each do |fc, _bg|
        @ctx.add_frame(id, "final_#{id}", a.input_sym, 4, fc)
      end
      @ctx.register_event(id, "scene_complete", "burn", "scene", "final_#{id}")
      @ctx.register_event(id, "scene_complete", "burn", "callback", 0)
    end
    @link_order = algo.char_link_order
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @link_order.empty? && @ctx.active_empty?
      n = @ctx.rng.randint(2, 4)
      n.times do
        break if @link_order.empty?
        id = @link_order.shift
        unless @ctx.anim(id).input_sym == " "
          @ctx.activate_scene(id, "burn")
          @ctx.active_include(id)
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
