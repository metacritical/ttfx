# Run loops: legacy full-canvas repaint for the simplified effects, plus the
# faithful frame loop (shared by ANSI, --dump-frames, and raylib) for
# scene-machine effects like decrypt.
class Engine
  FRAME_SLEEP = 1.0 / 60.0

  attr_reader :canvas, :rng
  attr_accessor :frame_count

  def initialize(canvas, rng)
    @canvas = canvas
    @rng = rng
    @frame_count = 0
  end

  def run(effect)
    out = $stdout
    out.print(Terminal::ANSI_HIDE_CURSOR)
    loop do
      draws = effect.next_frame
      break if draws.nil?
      render(draws)
      @frame_count += 1
      sleep(FRAME_SLEEP)
    end
    out.print(Terminal::ANSI_SHOW_CURSOR)
  end

  def render(draws)
    parts = [Terminal::ANSI_HOME]
    r = 0
    while r < @canvas.rows
      parts.push(" " * @canvas.cols)
      parts.push("\e[0m\n") if r < @canvas.rows - 1
      r += 1
    end
    parts.push(Terminal::ANSI_HOME)
    i = 0
    while i < draws.length
      d = draws[i]
      row = d[0]
      col = d[1]
      sym = d[2]
      fg = d[3]
      if row >= 0 && row < @canvas.rows && col >= 0 && col < @canvas.cols
        parts.push("\e[#{row + 1};#{col + 1}H")
        parts.push(fg.nil? ? "" : Color.fg(fg))
        parts.push(sym)
      end
      i += 1
    end
    parts.push(Color::RESET)
    $stdout.print(parts.join)
    $stdout.flush
  end
end

# Faithful loop: each next_frame is already a full frame string.
module FaithfulRun
  def self.live(ctx, effect)
    out = $stdout
    out.print(Terminal::ANSI_HIDE_CURSOR)
    loop do
      frame = effect.next_frame
      break if frame.nil?
      out.print(Terminal::ANSI_HOME)
      out.print(frame)
      out.flush
      sleep(1.0 / ctx.frame_rate.to_f) unless ctx.frame_rate == 0
    end
    out.print(Terminal::ANSI_SHOW_CURSOR)
    out.flush
  end

  # Deterministic dump: "{byte_len}\n{frame}\n" per frame on stdout,
  # "frames=N" on stderr. max_frames nil/0 means no cap. Uses the virtual
  # clock (1/frame_rate per frame, like --virtual-clock).
  def self.dump(ctx, effect, max_frames)
    ctx.use_virtual_clock
    count = 0
    loop do
      frame = effect.next_frame
      break if frame.nil?
      $stdout.puts(frame.bytesize)
      $stdout.print(frame)
      $stdout.print("\n")
      ctx.tick_clock
      count += 1
      break if !max_frames.nil? && max_frames > 0 && count >= max_frames
    end
    STDERR.puts("frames=#{count}")
    count
  end
end
