# Faithful matrix (ttfx src/effects/matrix.rs, old-engine semantics).
#
# THE CLOCK EFFECT: rain falls for rain_time seconds (wall clock live,
# virtual 1/frame_rate clock in --dump-frames, mirroring --virtual-clock),
# then columns fill and characters resolve into the final gradient.
class RainColumn
  attr_accessor :chars, :pending, :visible, :phase, :drop_chance
  attr_accessor :base_delay, :active_delay, :length, :hold

  def initialize
    @chars = []
    @pending = []
    @visible = []
    @phase = "rain"
    @drop_chance = 0.08
    @base_delay = 0
    @active_delay = 0
    @length = 0
    @hold = 0
  end

  def setup(ctx, fall_lo, fall_hi, phase)
    @pending = []
    @phase = phase
    @chars.each do |id|
      a = ctx.anim(id)
      ctx.set_visible(id, false)
      @pending.push(id)
      ctx.motion_set_coordinate(id, a.input_col, a.input_row)
    end
    @visible = []
    if phase == "fill"
      lo = fall_lo / 3
      lo = 1 if lo < 1
      hi = fall_hi / 3
      hi = 1 if hi < 1
      @base_delay = ctx.rng.randint(lo, hi)
    else
      @base_delay = ctx.rng.randint(fall_lo, fall_hi)
    end
    @active_delay = 0
    if phase == "rain"
      lo = (@chars.length.to_f * 0.1).to_i
      lo = 1 if lo < 1
      @length = ctx.rng.randint(lo, @chars.length)
    else
      @length = @chars.length
    end
    @hold = 0
    @hold = ctx.rng.randint(20, 45) if @length == @chars.length
  end

  def trim(ctx, rain_colors)
    return if @visible.empty?
    popped = @visible.shift
    ctx.set_visible(popped, false)
    fade_last(ctx, rain_colors) if @visible.length > 1
  end

  def drop(ctx)
    bottom = ctx.canvas.bottom
    out = []
    @visible.each do |id|
      a = ctx.anim(id)
      ctx.motion_set_coordinate(id, a.cur_col, a.cur_row - 1)
      if a.cur_row < bottom
        ctx.set_visible(id, false)
        out.push(id)
      end
    end
    out.each { |id| @visible.delete(id) }
  end

  def fade_last(ctx, rain_colors)
    tail = rain_colors[rain_colors.length - 3, 3]
    darker = Color.adjust_brightness(ctx.rng.choice(tail), 0.65)
    target = @visible[0]
    sym = ctx.anim(target).cur_sym
    ctx.set_appearance(target, sym, darker)
  end

  def resolve_char(ctx)
    idx = ctx.rng.randint(0, @visible.length - 1)
    @visible.delete_at(idx)
  end

  def tick(ctx, cfg)
    if @active_delay == 0
      unless @pending.empty?
        id = @pending.shift
        sym = ctx.rng.choice(cfg.rain_symbols)
        ctx.set_appearance(id, sym, cfg.highlight_color)
        prev = @visible[@visible.length - 1]
        unless prev.nil?
          psym = ctx.anim(prev).cur_sym
          ctx.set_appearance(prev, psym, ctx.rng.choice(cfg.rain_colors))
        end
        ctx.set_visible(id, true)
        @visible.push(id)
      else
        unless @visible.empty?
          last = @visible[@visible.length - 1]
          if ctx.anim(last).cur_fg == cfg.highlight_color
            sym = ctx.anim(last).cur_sym
            ctx.set_appearance(last, sym, ctx.rng.choice(cfg.rain_colors))
          end
          if @hold != 0
            @hold -= 1
          elsif @phase == "rain"
            drop(ctx) if ctx.rng.random < @drop_chance
            trim(ctx, cfg.rain_colors)
          end
        end
      end
      trim(ctx, cfg.rain_colors) if @visible.length > @length
      @active_delay = @base_delay
    else
      @active_delay -= 1
    end
    @visible.each do |id|
      nsym = nil
      ncol = nil
      if ctx.rng.random < cfg.symbol_swap_chance
        nsym = ctx.rng.choice(cfg.rain_symbols)
      end
      if ctx.rng.random < cfg.color_swap_chance
        ncol = ctx.rng.choice(cfg.rain_colors)
      end
      next if nsym.nil? && ncol.nil?
      a = ctx.anim(id)
      same_sym = nsym.nil? || nsym == a.cur_sym
      same_col = ncol.nil? || ncol == a.cur_fg
      next if same_sym && same_col
      fsym = nsym.nil? ? a.cur_sym : nsym
      fcol = ncol.nil? ? a.cur_fg : ncol
      ctx.set_appearance(id, fsym, fcol)
    end
  end
end

class MatrixEffect
  attr_reader :rain_symbols, :rain_colors, :highlight_color
  attr_reader :symbol_swap_chance, :color_swap_chance

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @highlight_color = Color.from_hex(o.fetch("highlight_color", "dbffdb"))
    rain_hex = o.fetch("rain_color_gradient", ["92be92", "185318"])
    @rain_symbols = o.fetch("rain_symbols", ["2", "5", "9", "8", "Z", "*", ")", ":", ".", "\"", "=", "+", "-", "\u00a6", "|", "_", "\uff66", "\uff71", "\uff73", "\uff74", "\uff75", "\uff76", "\uff77", "\uff79", "\uff7a", "\uff7b", "\uff7c", "\uff7d", "\uff7e", "\uff7f", "\uff80", "\uff82", "\uff83", "\uff85", "\uff86", "\uff87", "\uff88", "\uff8a", "\uff8b", "\uff8e", "\uff8f", "\uff90", "\uff91", "\uff92", "\uff93", "\uff94", "\uff95", "\uff97", "\uff98", "\uff9c"])
    fall = o.fetch("rain_fall_delay_range", [2, 15])
    @fall_lo = fall[0]
    @fall_hi = fall[1]
    cold = o.fetch("rain_column_delay_range", [3, 9])
    @col_lo = cold[0]
    @col_hi = cold[1]
    @rain_time = o.fetch("rain_time", 15)
    @symbol_swap_chance = o.fetch("symbol_swap_chance", 0.005)
    @color_swap_chance = o.fetch("color_swap_chance", 0.001)
    @resolve_delay_default = o.fetch("resolve_delay", 3)
    stop_hex = o.fetch("final_gradient_stops", ["92be92", "336b33"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_frames = o.fetch("final_gradient_frames", 3)
    @final_direction = o.fetch("final_gradient_direction", "radial")
    @rain_colors_stops = rain_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @columns = []
    @pending_columns = []
    @active_columns = []
    @full_columns = []
    @rain_colors = []
    @column_delay = 0
    @resolve_delay = @resolve_delay_default
    @final_shown = false
    @rain_complete = false
    @phase = "rain"
    @rain_start = 0.0
  end

  def build
    @rain_colors = Gradient.with_steps(@rain_colors_stops, 6, false).spectrum
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @ctx.new_scene(id, "resolve_#{id}")
      rg = Gradient.with_steps([@highlight_color, final], 8, false)
      pairs = rg.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "resolve_#{id}", [a.input_sym], @final_frames, pairs)
    end
    all = cv.all_ids
    cv.grouped_ids("column_left_to_right", all).each do |col_chars|
      col = RainColumn.new
      col.chars = col_chars.reverse
      col.setup(@ctx, @fall_lo, @fall_hi, "rain")
      @columns.push(col)
      @pending_columns.push(@columns.length - 1)
    end
    @ctx.rng.shuffle(@pending_columns)
    @rain_start = @ctx.now_wall
  end

  def column_phase
    @phase == "rain" ? "rain" : "fill"
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    if @phase == "rain" || @phase == "fill"
      if @column_delay == 0
        if @phase == "rain"
          n = @ctx.rng.randint(1, 3)
          n.times do
            break if @pending_columns.empty?
            @active_columns.push(@pending_columns.shift)
          end
        else
          until @pending_columns.empty?
            @active_columns.push(@pending_columns.shift)
          end
        end
        if @phase == "rain"
          @column_delay = @ctx.rng.randint(@col_lo, @col_hi)
        else
          @column_delay = 1
        end
      else
        @column_delay -= 1
      end
      snap = @active_columns.dup
      snap.each do |ci|
        @columns[ci].tick(@ctx, self)
        col = @columns[ci]
        if col.pending.empty?
          if col.phase == "fill" && !@full_columns.include?(ci)
            @full_columns.push(ci)
          elsif col.visible.empty?
            col.setup(@ctx, @fall_lo, @fall_hi, column_phase)
            @pending_columns.push(ci)
          end
        end
      end
      @active_columns = @active_columns.select { |ci| !@columns[ci].visible.empty? }
      if @phase == "fill" && @pending_columns.empty? &&
         @active_columns.all? { |ci| @columns[ci].pending.empty? && @columns[ci].phase == "fill" }
        @phase = "resolve"
        @active_columns = []
      end
      if @phase == "rain" && @rain_time > 0 &&
         @ctx.now_wall - @rain_start > @rain_time.to_f
        @rain_complete = true
        @phase = "fill"
        @active_columns.each do |ci|
          @columns[ci].hold = 0
          @columns[ci].drop_chance = 1.0
        end
        snap2 = @pending_columns.dup
        snap2.each do |ci|
          @columns[ci].setup(@ctx, @fall_lo, @fall_hi, "fill")
        end
      end
    elsif @phase == "resolve"
      snap = @full_columns.dup
      snap.each do |ci|
        @columns[ci].tick(@ctx, self)
        unless @columns[ci].visible.empty?
          if @resolve_delay == 0
            n = @ctx.rng.randint(1, 4)
            n.times do
              break if @columns[ci].visible.empty?
              nid = @columns[ci].resolve_char(@ctx)
              if @ctx.anim(nid).input_sym != " "
                @ctx.activate_scene(nid, "resolve_#{nid}")
                @ctx.active_include(nid)
              else
                @ctx.set_visible(nid, false)
              end
            end
            @resolve_delay = @resolve_delay_default
          else
            @resolve_delay -= 1
          end
        end
      end
      @full_columns = @full_columns.select { |ci| !@columns[ci].visible.empty? }
    end
    unless !@full_columns.empty? || !@active_columns.empty? ||
           !@ctx.active_empty? || !@pending_columns.empty? || !@rain_complete
      if !@final_shown
        @final_shown = true
        @ctx.update(self)
        return @ctx.frame_string
      end
      return nil
    end
    @ctx.update(self)
    @ctx.frame_string
  end
end
