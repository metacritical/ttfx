# Faithful decrypt (ttfx src/effects/decrypt.rs, old-engine semantics).
#
# Two phases: typing (block chars resolving to one cipher symbol) then
# decrypting (80 fast cipher frames, 1-15 slow frames with usually-short or
# occasionally-long durations, then white -> final-color discovered frames).
# Every RNG draw mirrors the Rust build order exactly.
class DecryptEffect
  BLOCKS = ["\u2589", "\u2593", "\u2592", "\u2591"].freeze

  attr_reader :config

  def initialize(ctx, opts = nil)
    @ctx = ctx
    o = opts || {}
    @typing_speed = o.fetch("typing_speed", 2)
    cipher_hex = o.fetch("ciphertext_colors", ["008000", "00cb00", "00ff00"])
    stop_hex = o.fetch("final_gradient_stops", ["eda000"])
    @final_steps = o.fetch("final_gradient_steps", [12])
    @final_direction = o.fetch("final_gradient_direction", "vertical")
    @cipher_colors = cipher_hex.map { |h| Color.from_hex(h) }
    @final_stops = stop_hex.map { |h| Color.from_hex(h) }
    @phase = "typing"
    @typing_pending = []
    @decrypting_pending = []
    @final_map = {}
    @symbols = []
  end

  def make_symbols
    n = 33
    while n < 127
      @symbols.push(n.chr(Encoding::UTF_8))
      n += 1
    end
    n = 9608
    while n < 9632
      @symbols.push(n.chr(Encoding::UTF_8))
      n += 1
    end
    n = 9472
    while n < 9599
      @symbols.push(n.chr(Encoding::UTF_8))
      n += 1
    end
    n = 174
    while n < 452
      @symbols.push(n.chr(Encoding::UTF_8))
      n += 1
    end
  end

  def choose_cipher
    @ctx.rng.choice(@cipher_colors)
  end

  def choose_symbol
    @ctx.rng.choice(@symbols)
  end

  def build
    make_symbols
    grad = Gradient.build(@final_stops, @final_steps, false, false)
    cv = @ctx.canvas
    mapping = grad.coord_map(cv.text_bottom, cv.text_top, cv.text_left, cv.text_right, @final_direction)
    order = cv.ordered_ids
    order.each do |id|
      a = @ctx.anim(id)
      final = mapping.get(a.input_col, a.input_row)
      @final_map[id] = final
    end
    prepare_typing(order)
    prepare_decrypting(order)
  end

  def prepare_typing(order)
    order.each do |id|
      @ctx.new_scene(id, "typing")
      BLOCKS.each do |b|
        @ctx.add_frame(id, "typing", b, 2, choose_cipher)
      end
      @ctx.add_frame(id, "typing", choose_symbol, 1, choose_cipher)
      @typing_pending.push(id)
    end
  end

  def prepare_decrypting(order)
    order.each do |id|
      a = @ctx.anim(id)
      # fast_decrypt: one color, 80 random symbols of duration 2
      @ctx.new_scene(id, "fast_decrypt")
      color = choose_cipher
      80.times do
        @ctx.add_frame(id, "fast_decrypt", choose_symbol, 2, color)
      end
      # slow_decrypt: 1-15 frames of long or flickering durations
      @ctx.new_scene(id, "slow_decrypt")
      count = @ctx.rng.randint(1, 15)
      count.times do
        sym = choose_symbol
        dur = 0
        if @ctx.rng.randint(0, 100) <= 30
          dur = @ctx.rng.randrange(35, 60)
        else
          dur = @ctx.rng.randrange(3, 6)
        end
        @ctx.add_frame(id, "slow_decrypt", sym, dur, color)
      end
      # discovered: white -> final color in 10 steps, duration 5
      @ctx.new_scene(id, "discovered")
      white = [255, 255, 255]
      final = @final_map[id]
      disc = Gradient.with_steps([white, final], 10, false)
      pairs = disc.spectrum.map { |c| [c, nil] }
      @ctx.apply_gradient(id, "discovered", [a.input_sym], 5, pairs)
      @ctx.register_event(id, "scene_complete", "fast_decrypt", "scene", "slow_decrypt")
      @ctx.register_event(id, "scene_complete", "slow_decrypt", "scene", "discovered")
      @ctx.activate_scene(id, "fast_decrypt")
      @decrypting_pending.push(id)
    end
  end

  # Returns the frame string, or nil when the animation is complete.
  def next_frame
    if @phase == "typing"
      if !@typing_pending.empty? || !@ctx.active_empty?
        if !@typing_pending.empty? && @ctx.rng.randint(0, 100) <= 75
          k = 0
          while k < @typing_speed
            break if @typing_pending.empty?
            id = @typing_pending.shift
            @ctx.set_visible(id, true)
            @ctx.activate_scene(id, "typing")
            @ctx.active_include(id)
            k += 1
          end
        end
        @ctx.update(self)
        return @ctx.frame_string
      end
      @ctx.active_clear
      @decrypting_pending.each do |id|
        @ctx.active_include(id)
        @ctx.activate_scene(id, "fast_decrypt")
      end
      @phase = "decrypting"
    end
    if @phase == "decrypting"
      unless @ctx.active_empty?
        @ctx.update(self)
        return @ctx.frame_string
      end
      return nil
    end
    nil
  end
end
