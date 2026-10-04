# Faithful slice (ttfx src/effects/slice.rs, old-engine semantics).
#
# The input is sliced in half and slides in from opposite edges: top/bottom
# (vertical), left/right (horizontal, double speed, fills included), or
# bottom/top diagonals. Characters carry their final colors from the start;
# only motion animates. Fully deterministic (no RNG draws).
class SliceEffect
  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @direction = o.fetch("slice_direction", "vertical")
    @speed = o.fetch("movement_speed", 0.25)
    @ease = o.fetch("movement_easing", "in_out_expo")
    stop_hex = o.fetch("final_gradient_stops", ["8A008A", "00D1FF", "FFFFFF"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "diagonal")
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
  end

  def send_to(id, ocol, orow)
    a = @ctx.anim(id)
    @ctx.motion_set_coordinate(id, ocol, orow)
    pname = @ctx.motion_new_path(id, "", @speed, @ease, 0, false)
    @ctx.motion_add_waypoint(id, pname, a.input_col, a.input_row)
    @ctx.motion_activate_path(id, pname)
  end

  def build
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @ctx.set_appearance(id, a.input_sym, final)
    end
    top = cv.top
    bottom = cv.bottom
    left = cv.left
    right = cv.right
    cc = cv.text_center_column
    if @direction == "vertical"
      rows = cv.grouped_ids("row_bottom_to_top")
      i = 0
      while i < rows.length
        row = rows[i]
        left_half = row.select do |id|
          @ctx.anim(id).input_col <= cc
        end
        left_half.each do |id|
          send_to(id, @ctx.anim(id).input_col, top + 1)
        end
        orow = rows[rows.length - (i + 1)]
        right_half = orow.select do |id|
          @ctx.anim(id).input_col > cc
        end
        right_half.each do |id|
          send_to(id, @ctx.anim(id).input_col, bottom - 1)
        end
        left_half.each { |id| @ctx.active_include(id) }
        right_half.each { |id| @ctx.active_include(id) }
        i += 1
      end
    elsif @direction == "horizontal"
      @speed *= 2.0
      cols = cv.grouped_ids("column_right_to_left", cv.all_ids)
      trimmed = []
      cols.each do |col|
        nc = col.select do |id|
          a = @ctx.anim(id)
          a.input_col >= cv.text_left && a.input_col <= cv.text_right &&
            a.input_row >= cv.text_bottom && a.input_row <= cv.text_top
        end
        trimmed.push(nc) unless nc.empty?
      end
      mid = cv.text_center_row
      i = 0
      while i < trimmed.length
        col = trimmed[i]
        bottom_half = col.select { |id| @ctx.anim(id).input_row <= mid }
        bottom_half.each do |id|
          send_to(id, left - 1, @ctx.anim(id).input_row)
        end
        ocol = trimmed[trimmed.length - (i + 1)]
        top_half = ocol.select { |id| @ctx.anim(id).input_row > mid }
        top_half.each do |id|
          send_to(id, right + 1, @ctx.anim(id).input_row)
        end
        bottom_half.each { |id| @ctx.active_include(id) }
        top_half.each { |id| @ctx.active_include(id) }
        i += 1
      end
    elsif @direction == "diagonal"
      diags = cv.grouped_ids("diagonal_bottom_left_to_top_right")
      half = diags.length / 2
      left_groups = diags[0, half]
      right_groups = diags[half, diags.length]
      until left_groups.empty? && right_groups.empty?
        unless left_groups.empty?
          lg = left_groups.shift
          ocol = @ctx.anim(lg[0]).input_col
          lg.each { |id| send_to(id, ocol, bottom - 1) }
          lg.each { |id| @ctx.active_include(id) }
        end
        unless right_groups.empty?
          rg = right_groups.shift
          ocol = @ctx.anim(rg[rg.length - 1]).input_col
          rg.each { |id| send_to(id, ocol, top + 1) }
          rg.each { |id| @ctx.active_include(id) }
        end
      end
    end
    snap = @ctx.active_snapshot
    snap.each do |id|
      @ctx.set_visible(id, true)
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    unless @ctx.active_empty?
      @ctx.update(self)
      return @ctx.frame_string
    end
    nil
  end
end
