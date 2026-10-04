# Ruby regression tests for deterministic effect behavior.
#
# Run with: ruby -I. test/test_faithful_effects.rb
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "ttfx"

class FaithfulEffectsTest < Minitest::Test
  GOLDENS = JSON.parse(File.read(File.expand_path("fixtures/effect_goldens.json", __dir__))).freeze

  def test_every_registered_effect_matches_its_rust_frame_stream
    assert_equal Effects.names.sort, GOLDENS.keys.sort, "golden fixture must cover every registered effect"
    GOLDENS.each do |name, fixture|
      assert_equal "faithful", Effects.kind(name), "#{name} must be registered as faithful"
      assert_rust_golden(name, fixture)
    end
  end

  def test_synthgrid_logo_matches_rust_frame_stream
    assert_rust_golden("synthgrid", {
      "input" => File.read(File.expand_path("../logo.txt", __dir__)),
      "seed" => 7,
      "frames" => 423,
      "sha256" => "d687ba8b21076d685217030dc4f22712043f767467d50fc12871b886f208fb88"
    })
  end


  def test_rng_seed_sequence_and_shuffle_are_stable
    rng = Rng.new(42)
    word = rng.next_word
    value = word[0] + (word[1] << 16) + (word[2] << 32) + (word[3] << 48)
    assert_equal 0xd0764d4f4476689f, value

    seq = [0, 1, 2, 3, 4]
    Rng.new(42).shuffle(seq)
    assert_equal [0, 1, 4, 3, 2], seq
  end

  def test_canvas_layout_preserves_row_major_input_positions
    canvas = Canvas.new(3, 5, "ab\nc")
    actual = canvas.ordered_ids.map do |id|
      char = canvas.anims[id]
      [char.input_sym, char.input_col, char.input_row]
    end
    assert_equal [["a", 1, 2], ["b", 2, 2], ["c", 1, 1]], actual
  end

  def test_scene_durations_and_activation
    canvas = Canvas.new(1, 1, "x")
    ctx = EngineCtx.new(canvas, Rng.new(1))
    id = canvas.ordered_ids.first
    ctx.new_scene(id, "typing")
    ctx.add_frame(id, "typing", "A", 2, [255, 0, 0])
    ctx.add_frame(id, "typing", "B", 1, [0, 255, 0])
    ctx.activate_scene(id, "typing")
    ctx.set_visible(id, true)
    ctx.active_include(id)

    actual = []
    3.times do
      ctx.update
      actual << ctx.anim(id).cur_sym
    end
    assert_equal ["A", "A", "B"], actual
    assert ctx.active_empty?
  end

  def test_cli_list_matches_registered_effects
    root = File.expand_path("..", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I.", "bin/ttfx.rb", "--list", chdir: root)
    assert status.success?, stderr
    listed = stdout.lines.map { |line| line.split(":", 2).first }
    assert_equal Effects.names, listed
  end

  def test_cubic_bezier_easing_handles_endpoints_and_overshoot_curve
    curve = [0.0, 1.6, 1.0, -0.2]
    assert_equal 0.0, Easing.ease(curve, 0.0)
    assert_equal 1.0, Easing.ease(curve, 1.0)
    assert_in_delta 0.65, Easing.ease(curve, 0.5), 0.01
  end

  private

  def assert_rust_golden(effect_name, fixture)
    input = fixture.fetch("input")
    seed = fixture.fetch("seed")
    count = fixture.fetch("frames")
    expected_sha = fixture.fetch("sha256")
    options = fixture.fetch("options", {})
    canvas = Canvas.new(24, 80, input)
    ctx = EngineCtx.new(canvas, Rng.new(seed))
    ctx.frame_rate = 60
    ctx.use_virtual_clock
    effect_class = Effects::REGISTRY.fetch(effect_name)[1]
    effect = effect_class.new(ctx, options)
    effect.build

    serialized = +""
    actual_count = 0
    loop do
      frame = effect.next_frame
      break if frame.nil?
      serialized << frame.bytesize.to_s << "\n" << frame << "\n"
      actual_count += 1
      ctx.tick_clock
      assert_operator actual_count, :<=, count, "#{effect_name} exceeded its expected frame count"
    end

    assert_equal count, actual_count, "#{effect_name} frame count changed"
    assert_equal expected_sha, Digest::SHA256.hexdigest(serialized), "#{effect_name} frame stream diverged from Rust"
  end
end
