# Particle pool (ttfx src/engine/particles.rs).
#
# Preallocated arena characters recycled as particles. Available queue pops
# from the back; reclaim is idempotent. Initializers run explicitly in the
# effect (no closures cross into the pool).
class ParticlePool
  attr_reader :particles

  def initialize(symbols, max_size, coord = nil)
    raise "ParticlePool requires at least one symbol." if symbols.empty?
    @symbols = symbols
    @max_size = max_size
    @coord = coord.nil? ? [0, 0] : coord
    @available = []
    @particles = []
  end

  # Preallocate: choice symbol + arena character per slot (no init).
  def preallocate(ctx, count)
    if !@max_size.nil? && @max_size < count
      raise "max_size must be greater than or equal to initial_count."
    end
    count.times do
      sym = ctx.rng.choice(@symbols)
      id = ctx.add_character(sym, @coord[0], @coord[1])
      @particles.push(id)
      @available.push(id)
    end
  end

  def self.reset_particle(ctx, id, clear_paths, deactivate_path, deactivate_scene)
    a = ctx.anim(id)
    a.active_path = nil if deactivate_path
    a.active = nil if deactivate_scene
    a.paths.clear if clear_paths
  end

  # Pop an available particle (reset to defaults) or nil when exhausted.
  def acquire(ctx)
    return nil if @available.empty?
    id = @available.pop
    ParticlePool.reset_particle(ctx, id, true, true, true)
    id
  end

  def reclaim(ctx, id, hide, deactivate)
    ctx.set_visible(id, false) if hide
    if deactivate
      a = ctx.anim(id)
      a.active_path = nil
      a.active = nil
    end
    ctx.active.delete(id)
    @available.push(id) unless @available.include?(id)
  end
end

# Prim's link-order generator (primssimple.py).
class PrimsSimple
  attr_reader :complete, :char_link_order

  def initialize(ctx, starting, limit_to_text)
    @limit = limit_to_text
    if starting.nil?
      starting = SpanningTree.default_starting_char(ctx, limit_to_text)
      raise "Unable to find a starting character." if starting.nil?
    end
    @current = starting
    @last_linked = starting
    @char_link_order = [starting]
    @edge_chars = [starting]
    @edge_added = starting
    @edge_popped = nil
    @complete = false
  end

  def step(ctx)
    unless @edge_chars.empty?
      idx = ctx.rng.randrange(0, @edge_chars.length)
      @current = @edge_chars.delete_at(idx)
      @edge_popped = @current
      unlinked = SpanningTree.neighbors(ctx, @current, true, @limit)
      unless unlinked.empty?
        nidx = ctx.rng.randrange(0, unlinked.length)
        nxt = unlinked.delete_at(nidx)
        SpanningTree.link_characters(ctx, @current, nxt)
        @char_link_order.push(nxt)
        @last_linked = nxt
        @edge_chars.push(@current) unless unlinked.empty?
        nn = SpanningTree.neighbors(ctx, nxt, true, @limit)
        unless nn.empty?
          @edge_chars.push(nxt)
          @edge_added = nxt
        end
      end
    else
      @complete = true
    end
  end
end
