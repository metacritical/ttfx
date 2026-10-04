# Spanning-tree generators (ttfx src/utils/spanning_tree.rs).
# Links stay id-sorted (canonical order); BreadthFirst consumes no RNG.
module SpanningTree
  def self.link_characters(ctx, a, b)
    la = ctx.anim(a).links
    unless la.include?(b)
      ctx.anim(a).links = (la + [b]).sort
    end
    lb = ctx.anim(b).links
    unless lb.include?(a)
      ctx.anim(b).links = (lb + [a]).sort
    end
  end

  def self.neighbors(ctx, id, unlinked_only, limit_to_text)
    a = ctx.anim(id)
    out = []
    [a.north, a.east, a.south, a.west].each do |n|
      next if n.nil?
      if limit_to_text
        c = ctx.anim(n)
        cv = ctx.canvas
        next unless c.input_col >= cv.text_left && c.input_col <= cv.text_right &&
                    c.input_row >= cv.text_bottom && c.input_row <= cv.text_top
      end
      if unlinked_only
        next unless ctx.anim(n).links.empty?
      end
      out.push(n)
    end
    out
  end

  def self.default_starting_char(ctx, within_text)
    coord = ctx.canvas.random_coord(ctx.rng, false, within_text)
    ctx.canvas.char_by_coord(coord[0], coord[1])
  end
end

# Weighted Prim's (primsweighted.py).
class PrimsWeighted
  attr_reader :complete

  def initialize(ctx, starting, limit_to_text)
    @limit = limit_to_text
    if starting.nil?
      starting = SpanningTree.default_starting_char(ctx, limit_to_text)
      raise "Unable to find a starting character." if starting.nil?
    end
    ordered = ctx.canvas.ordered_ids(ctx.canvas.all_ids)
    @weights = {}
    ordered.each do |id|
      @weights[id] = ctx.rng.randint(0, 99)
    end
    @last_linked = starting
    @link_order = [starting]
    @neighbors_added = []
    @complete = false
    @pending = {}
    add_links(ctx, starting)
  end

  def add_links(ctx, id)
    @neighbors_added = []
    SpanningTree.neighbors(ctx, id, true, @limit).each do |n|
      @neighbors_added.push(n)
      w = @weights[n]
      list = @pending[w]
      if list.nil?
        list = []
        @pending[w] = list
      end
      list.push([id, n, w])
    end
  end

  def lowest_link(ctx)
    until @pending.empty?
      w = @pending.keys.min
      list = @pending[w]
      idx = ctx.rng.randrange(0, list.length)
      link = list.delete_at(idx)
      @pending.delete(w) if list.empty?
      return link if ctx.anim(link[1]).links.empty?
    end
    nil
  end

  def step(ctx)
    unless @pending.empty?
      link = lowest_link(ctx)
      if link.nil?
        @complete = true
        return
      end
      SpanningTree.link_characters(ctx, link[0], link[1])
      @last_linked = link[1]
      @link_order.push(link[1])
      add_links(ctx, link[1])
    else
      @complete = true
      @last_linked = nil
      @neighbors_added = []
    end
  end
end

# Recursive backtracker used by laseretch (src/utils/spanning_tree.rs).
class RecursiveBacktracker
  attr_reader :complete, :char_link_order

  def initialize(ctx, starting, limit_to_text)
    @limit = limit_to_text
    @current = starting.nil? ? SpanningTree.default_starting_char(ctx, limit_to_text) : starting
    raise "Unable to find a starting character." if @current.nil?
    @stack = [@current]
    @char_link_order = [@current]
    @complete = false
  end

  def step(ctx)
    if @stack.empty?
      @complete = true
      return
    end
    unvisited = SpanningTree.neighbors(ctx, @current, true, @limit)
    if !unvisited.empty?
      next_id = ctx.rng.choice(unvisited)
      SpanningTree.link_characters(ctx, @current, next_id)
      @char_link_order.push(next_id)
      @stack.push(next_id)
      @current = next_id
    else
      @stack.pop
      @current = @stack[-1] unless @stack.empty?
    end
  end
end

# Layer-by-layer traversal of the linked graph (breadthfirst.py).
class BreadthFirst
  attr_reader :complete, :starting_char, :explored_last_step

  def initialize(ctx, starting, limit_to_text)
    @limit = limit_to_text
    if starting.nil?
      starting = SpanningTree.default_starting_char(ctx, limit_to_text)
      raise "Unable to find a starting character." if starting.nil?
    end
    @starting_char = starting
    @frontier = [starting]
    @explored = { starting => true }
    @explored_last_step = []
    @explore_order = []
    @complete = false
  end

  def step(ctx)
    @explored_last_step = []
    if @frontier.empty?
      @complete = true
      return
    end
    new_edges = []
    until @frontier.empty?
      pos = @frontier.shift
      links = ctx.anim(pos).links
      links.each do |n|
        next if @explored.key?(n) || @frontier.include?(n) || new_edges.include?(n)
        @explored[n] = true
        @explored_last_step.push(n)
        @explore_order.push(n)
        new_edges.push(n)
      end
    end
    @frontier = new_edges
  end
end
