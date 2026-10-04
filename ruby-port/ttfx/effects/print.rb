# Faithful print (ttfx src/effects/print_effect.rs, old-engine semantics).
#
# A typing head performs carriage returns between rows while characters
# type out left to right, earlier rows scrolling up. Fully deterministic
# (no RNG draws).
class PrintEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @return_speed = o.fetch("print_head_return_speed", 1.5)
    @print_speed = o.fetch("print_speed", 2)
    @head_ease = o.fetch("print_head_easing", "in_out_quad")
    stop_hex = o.fetch("final_gradient_stops", ["02b8bd", "c1f0e3", "00ffa0"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "diagonal")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @pending = []
    @processed = []
    @head = nil
    @final_map = {}
    @current = nil
    @typing = false
    @last_column = 0
  end

  def make_row(ids)
    if ids.all? { |id| @ctx.anim(id).input_sym == " " }
      chars = [ids[0]]
    else
      extent = 0
      ids.each do |id|
        a = @ctx.anim(id)
        extent = a.input_col if !a.is_fill && a.input_col > extent
      end
      chars = ids.select { |id| @ctx.anim(id).input_col <= extent }
    end
    untyped = []
    chars.each do |id|
      a = @ctx.anim(id)
      @ctx.motion_set_coordinate(id, a.input_col, 1)
      @ctx.new_scene(id, "print_#{id}")
      final = @final_map[id]
      fg = Gradient.with_steps([[255, 255, 255], final], 5, false)
      pairs = fg.spectrum.map { |c| [c, nil] }
      syms = ["\u2588", "\u2593", "\u2592", "\u2591", a.input_sym]
      @ctx.apply_gradient(id, "print_#{id}", syms, 3, pairs)
      @ctx.activate_scene(id, "print_#{id}")
      untyped.push(id)
    end
    [untyped, []]
  end

  def row_move_up(row)
    row[1].each do |id|
      a = @ctx.anim(id)
      @ctx.motion_set_coordinate(id, a.cur_col, a.cur_row + 1)
    end
  end

  def row_all_fill?(ids)
    ids.all? { |id| @ctx.anim(id).is_fill }
  end

  def build
    @head = @ctx.add_character("\u2588", 1, 1)
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    white = [255, 255, 255]
    all = cv.all_ids
    order = cv.ordered_ids(all)
    order.each do |id|
      a = @ctx.anim(id)
      @final_map[id] = mapping.get(a.input_col, a.input_row) || white
    end
    rows = cv.grouped_ids("row_top_to_bottom", all)
    rows.each do |row|
      @pending.push(make_row(row))
    end
    @current = @pending.shift
    @typing = true
    @last_column = 0
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    if !@ctx.active_empty? || @typing
      head_active = !@ctx.anim(@head).active_path.nil?
      if head_active
        # carriage return in progress
      elsif !@current[0].empty?
        n = @current[0].length
        n = @print_speed if n > @print_speed
        n.times do
          break if @current[0].empty?
          id = @current[0].shift
          @current[1].push(id)
          @ctx.set_visible(id, true)
          @ctx.active_include(id)
          @last_column = @ctx.anim(id).input_col
        end
      else
        @processed.push(@current)
        unless @pending.empty?
          @processed.each { |row| row_move_up(row) }
          @current = @pending.shift
          last_fill = row_all_fill?(@processed[@processed.length - 1][1])
          cur_fill = row_all_fill?(@current[0])
          if !last_fill && !cur_fill
            extent = nil
            @current[0].each do |id|
              a = @ctx.anim(id)
              if !a.is_fill && (extent.nil? || a.input_col < extent)
                extent = a.input_col
              end
            end
            tr = @ctx.canvas.text_right
            @current[0] = @current[0].select do |id|
              c = @ctx.anim(id).input_col
              extent <= c && c <= tr
            end
          end
          @ctx.motion_set_coordinate(@head, @last_column, 1)
          @ctx.set_visible(@head, true)
          target = @ctx.anim(@current[0][0]).input_col
          @ctx.anim(@head).paths.clear
          @ctx.motion_new_path(@head, "carriage_return_path", @return_speed, @head_ease, 0, false)
          @ctx.motion_add_waypoint(@head, "carriage_return_path", target, 1)
          @ctx.motion_activate_path(@head, "carriage_return_path")
          @ctx.register_event(@head, "path_complete", "carriage_return_path", "callback", 0)
          @ctx.active_include(@head)
        else
          @typing = false
        end
      end
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end

  def on_callback(ctx, id, cbid)
    ctx.set_visible(id, false) if cbid == 0
  end
end
