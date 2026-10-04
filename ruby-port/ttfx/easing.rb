# Faithful easing functions + trackers (ttfx src/utils/easing.rs).
#
# Transcription rule: Python `x ** n` routes through C `pow()`, so every
# power here is Float#** (verified identical in CRuby and Spinel).
# Names match the CLI spellings (in_out_circ, out_bounce, ...).
module Easing
  PI = 3.141592653589793

  def self.ease(name, p)
    return cubic_bezier(name[0], name[1], name[2], name[3], p) if name.is_a?(Array)
    case name
    when "linear" then p
    when "in_sine" then 1.0 - Math.cos((p * PI) / 2.0)
    when "out_sine" then Math.sin((p * PI) / 2.0)
    when "in_out_sine" then -(Math.cos(PI * p) - 1.0) / 2.0
    when "in_quad" then p ** 2.0
    when "out_quad" then 1.0 - (1.0 - p) * (1.0 - p)
    when "in_out_quad"
      if p < 0.5
        2.0 * (p ** 2.0)
      else
        1.0 - ((-2.0 * p + 2.0) ** 2.0) / 2.0
      end
    when "in_cubic" then p ** 3.0
    when "out_cubic" then 1.0 - (1.0 - p) ** 3.0
    when "in_out_cubic"
      if p < 0.5
        4.0 * (p ** 3.0)
      else
        1.0 - ((-2.0 * p + 2.0) ** 3.0) / 2.0
      end
    when "in_quart" then p ** 4.0
    when "out_quart" then 1.0 - (1.0 - p) ** 4.0
    when "in_out_quart"
      if p < 0.5
        8.0 * (p ** 4.0)
      else
        1.0 - ((-2.0 * p + 2.0) ** 4.0) / 2.0
      end
    when "in_quint" then p ** 5.0
    when "out_quint" then 1.0 - (1.0 - p) ** 5.0
    when "in_out_quint"
      if p < 0.5
        16.0 * (p ** 5.0)
      else
        1.0 - ((-2.0 * p + 2.0) ** 5.0) / 2.0
      end
    when "in_expo"
      p == 0.0 ? 0.0 : 2.0 ** (10.0 * p - 10.0)
    when "out_expo"
      p == 1.0 ? 1.0 : 1.0 - 2.0 ** (-10.0 * p)
    when "in_out_expo"
      if p == 0.0
        0.0
      elsif p == 1.0
        1.0
      elsif p < 0.5
        2.0 ** (20.0 * p - 10.0) / 2.0
      else
        (2.0 - 2.0 ** (-20.0 * p + 10.0)) / 2.0
      end
    when "in_circ" then 1.0 - Math.sqrt(1.0 - p ** 2.0)
    when "out_circ" then Math.sqrt(1.0 - (p - 1.0) ** 2.0)
    when "in_out_circ"
      if p < 0.5
        (1.0 - Math.sqrt(1.0 - (2.0 * p) ** 2.0)) / 2.0
      else
        (Math.sqrt(1.0 - (-2.0 * p + 2.0) ** 2.0) + 1.0) / 2.0
      end
    when "in_back"
      c1 = 1.70158
      c3 = c1 + 1.0
      c3 * (p ** 3.0) - c1 * (p ** 2.0)
    when "out_back"
      c1 = 1.70158
      c3 = c1 + 1.0
      1.0 + c3 * ((p - 1.0) ** 3.0) + c1 * ((p - 1.0) ** 2.0)
    when "in_out_back"
      c1 = 1.70158
      c2 = c1 * 1.525
      if p < 0.5
        ((2.0 * p) ** 2.0 * ((c2 + 1.0) * 2.0 * p - c2)) / 2.0
      else
        ((2.0 * p - 2.0) ** 2.0 * ((c2 + 1.0) * (p * 2.0 - 2.0) + c2) + 2.0) / 2.0
      end
    when "in_elastic"
      c4 = (2.0 * PI) / 3.0
      if p == 0.0
        0.0
      elsif p == 1.0
        1.0
      else
        -(2.0 ** (10.0 * p - 10.0)) * Math.sin((p * 10.0 - 10.75) * c4)
      end
    when "out_elastic"
      c4 = (2.0 * PI) / 3.0
      if p == 0.0
        0.0
      elsif p == 1.0
        1.0
      else
        2.0 ** (-10.0 * p) * Math.sin((p * 10.0 - 0.75) * c4) + 1.0
      end
    when "in_out_elastic"
      c5 = (2.0 * PI) / 4.5
      if p == 0.0
        0.0
      elsif p == 1.0
        1.0
      elsif p < 0.5
        -(2.0 ** (20.0 * p - 10.0) * Math.sin((20.0 * p - 11.125) * c5)) / 2.0
      else
        (2.0 ** (-20.0 * p + 10.0) * Math.sin((20.0 * p - 11.125) * c5)) / 2.0 + 1.0
      end
    when "in_bounce" then 1.0 - Easing.out_bounce(1.0 - p)
    when "out_bounce" then Easing.out_bounce(p)
    when "in_out_bounce"
      if p < 0.5
        (1.0 - Easing.out_bounce(1.0 - 2.0 * p)) / 2.0
      else
        (1.0 + Easing.out_bounce(2.0 * p - 1.0)) / 2.0
      end
    else p
    end
  end

  def self.out_bounce(p)
    n1 = 7.5625
    d1 = 2.75
    if p < 1.0 / d1
      n1 * (p ** 2.0)
    elsif p < 2.0 / d1
      n1 * ((p - 1.5 / d1) ** 2.0) + 0.75
    elsif p < 2.5 / d1
      n1 * ((p - 2.25 / d1) ** 2.0) + 0.9375
    else
      n1 * ((p - 2.625 / d1) ** 2.0) + 0.984375
    end
  end

  def self.valid_name?(name)
    ["linear", "in_sine", "out_sine", "in_out_sine", "in_quad", "out_quad",
     "in_out_quad", "in_cubic", "out_cubic", "in_out_cubic", "in_quart",
     "out_quart", "in_out_quart", "in_quint", "out_quint", "in_out_quint",
     "in_expo", "out_expo", "in_out_expo", "in_circ", "out_circ",
     "in_out_circ", "in_back", "out_back", "in_out_back", "in_elastic",
     "out_elastic", "in_out_elastic", "in_bounce", "out_bounce",
     "in_out_bounce"].include?(name)
  end

  # CSS-style cubic bezier easing used for a single thunderstorm flash. Solve
  # x(t)=p with the same Newton iteration and tolerances as the Rust engine.
  def self.cubic_bezier(x1, y1, x2, y2, progress)
    return 0.0 if progress <= 0.0
    return 1.0 if progress >= 1.0
    t = progress
    20.times do
      omt = 1.0 - t
      x = 3.0 * x1 * omt * omt * t + 3.0 * x2 * omt * t * t + t * t * t
      dx = x - progress
      break if dx.abs < 1e-5
      deriv = 3.0 * omt * omt * x1 + 6.0 * omt * t * (x2 - x1) + 3.0 * t * t * (1.0 - x2)
      break if deriv.abs < 1e-6
      t -= dx / deriv
    end
    omt = 1.0 - t
    3.0 * y1 * omt * omt * t + 3.0 * y2 * omt * t * t + t * t * t
  end
end

# EasingTracker: step counting with optional [0,1] clamping.
class EasingTracker
  attr_reader :eased_value

  def initialize(ease_name, total_steps, clamp)
    @ease_name = ease_name
    @total_steps = total_steps
    @clamp = clamp
    @current_step = 0
    @progress_ratio = 0.0
    @step_delta = 0.0
    @eased_value = 0.0
    @last_eased_value = 0.0
  end

  def step
    if @current_step < @total_steps
      @current_step += 1
      @progress_ratio = @current_step.to_f / @total_steps.to_f
      @eased_value = Easing.ease(@ease_name, @progress_ratio)
      if @clamp
        @eased_value = 1.0 if @eased_value > 1.0
        @eased_value = 0.0 if @eased_value < 0.0
      end
      @step_delta = @eased_value - @last_eased_value
      @last_eased_value = @eased_value
    end
    @eased_value
  end

  def complete?
    @current_step >= @total_steps
  end

  def reset
    @current_step = 0
    @progress_ratio = 0.0
    @step_delta = 0.0
    @eased_value = 0.0
    @last_eased_value = 0.0
  end
end

# SequenceEaser over owned groups: each step reports added/removed slices
# from int()-truncated eased positions (never both at once).
class SequenceEaser
  def initialize(sequence, ease_name, total_steps)
    @sequence = sequence
    @tracker = EasingTracker.new(ease_name, total_steps, true)
  end

  # Returns [added, removed].
  def step
    prev = @tracker.eased_value
    eased = @tracker.step
    n = @sequence.length
    return [[], []] if n == 0
    len = (eased * n.to_f).to_i
    prev_len = (prev * n.to_f).to_i
    if len > prev_len
      [@sequence[prev_len, len - prev_len], []]
    elsif len < prev_len
      [[], @sequence[len, prev_len - len]]
    else
      [[], []]
    end
  end

  def complete?
    @tracker.complete?
  end

  def reset
    @tracker.reset
  end

  # Swap in a new group sequence and restart (sweep phase change).
  def resequence(groups)
    @sequence = groups
    @tracker.reset
  end
end
