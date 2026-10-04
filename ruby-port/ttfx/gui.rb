# Raylib GUI front end: the same engine draws into a real window instead of
# ANSI escape sequences. Spinel's compile-time FFI links libraylib directly;
# ffi_source embeds the tiny C shim that adapts packed-integer colors to
# raylib's by-value Color struct.
module RL
  # Use compiler-default include and library paths. On macOS, users can set
  # CPATH/LIBRARY_PATH for a non-standard raylib prefix (e.g. Homebrew).
  ffi_lib "raylib"

  ffi_source <<~C
    #include <raylib.h>
    static Color rl_col(int p) {
      Color c;
      c.r = (unsigned char)(p & 0xff);
      c.g = (unsigned char)((p >> 8) & 0xff);
      c.b = (unsigned char)((p >> 16) & 0xff);
      c.a = (unsigned char)((p >> 24) & 0xff);
      return c;
    }
    static Font rl_font;
    static int rl_font_loaded = 0;
    static int rl_cps[1024];
    static int rl_cps_n = 0;
    void rl_font_load(const char *path) {
      if (rl_font_loaded) { UnloadFont(rl_font); rl_font_loaded = 0; }
      if (!rl_cps_n) {
        int i, n = 0;
        for (i = 32; i < 127; i++) rl_cps[n++] = i;
        for (i = 160; i < 256; i++) rl_cps[n++] = i;
        for (i = 0x100; i <= 0x17f; i++) rl_cps[n++] = i;
        for (i = 0x2500; i <= 0x25FF; i++) rl_cps[n++] = i;
        rl_cps_n = n;
      }
      rl_font = LoadFontEx(path, 48, rl_cps, rl_cps_n);
      rl_font_loaded = (rl_font.texture.id != 0);
    }
    int rl_font_ok(void) { return rl_font_loaded; }
    int rl_advance(const char *t, int size) {
      Vector2 v = rl_font_loaded
        ? MeasureTextEx(rl_font, t, (float)size, 0)
        : MeasureTextEx(GetFontDefault(), t, (float)size, 0);
      return (int)(v.x + 0.999f);
    }
    void rl_clear(int p) { ClearBackground(rl_col(p)); }
    void rl_text_f(const char *t, int x, int y, int size, int p) {
      Vector2 pos;
      pos.x = (float)x;
      pos.y = (float)y;
      if (rl_font_loaded) DrawTextEx(rl_font, t, pos, (float)size, 0, rl_col(p));
      else DrawText(t, x, y, size, rl_col(p));
    }
    void rl_rect(int x, int y, int w, int h, int p) {
      DrawRectangle(x, y, w, h, rl_col(p));
    }
  C

  ffi_func :InitWindow, [:int, :int, :str], :void
  ffi_func :CloseWindow, [], :void
  ffi_func :WindowShouldClose, [], :bool
  ffi_func :BeginDrawing, [], :void
  ffi_func :EndDrawing, [], :void
  ffi_func :GetScreenWidth, [], :int
  ffi_func :GetScreenHeight, [], :int
  ffi_func :SetWindowSize, [:int, :int], :void
  ffi_func :SetConfigFlags, [:int], :void
  ffi_func :ClearWindowState, [:int], :void
  ffi_func :SetTargetFPS, [:int], :void
  ffi_func :IsKeyPressed, [:int], :bool
  ffi_func :IsWindowFullscreen, [], :bool
  ffi_func :ToggleFullscreen, [], :void
  ffi_func :GetMonitorWidth, [:int], :int
  ffi_func :GetMonitorHeight, [:int], :int
  ffi_func :rl_font_load, [:str], :void
  ffi_func :rl_font_ok, [], :bool
  ffi_func :rl_advance, [:str, :int], :int
  ffi_const :KEY_ESCAPE, 256
  ffi_const :FLAG_FULLSCREEN_MODE, 2
  ffi_const :FLAG_WINDOW_HIDDEN, 128
  ffi_func :rl_clear, [:int], :void
  ffi_func :DrawFPS, [:int, :int], :void
  ffi_func :rl_text_f, [:str, :int, :int, :int, :int], :void
  ffi_func :rl_rect, [:int, :int, :int, :int, :int], :void
end

# Window loop over faithful frame cells ([row1, col1, sym, r, g, b]).
# Canvas row 1 is the bottom; window y grows downward. The window is sized
# exactly to the canvas (input-sized, up to 256x256), so text always fills
# it; --font-size scales the glyphs (cell keeps the 12:20 ratio).
class GuiEngine
  BG = 0xff181018

  attr_reader :canvas, :rng

  def initialize(canvas, rng, font_size = 36, fullscreen = true, font_path = nil, fps = 60, show_fps = false)
    @canvas = canvas
    @rng = rng
    @show_fps = show_fps
    @font = font_size < 8 ? 8 : font_size
    @cell_h = @font * 10 / 9
    @cell_h = 1 if @cell_h < 1
    if fullscreen
      # Fullscreen from the first frame: no intermediate window sizes.
      RL.SetConfigFlags(RL::FLAG_FULLSCREEN_MODE)
      RL.InitWindow(0, 0, "ttfx-rb (raylib)")
      @win_w = RL.GetScreenWidth
      @win_h = RL.GetScreenHeight
    else
      # Measure in a hidden window, then open fresh at the final size:
      # resizing a visible window blanks later drawing on macOS, so the
      # visible window is never resized after creation.
      RL.SetConfigFlags(RL::FLAG_WINDOW_HIDDEN)
      RL.InitWindow(480, 300, "ttfx-rb (raylib)")
      RL.SetTargetFPS(fps) unless fps == 0
      load_font(font_path)
      @cell_w = RL.rl_advance("█", @font)
      @cell_w = 1 if @cell_w < 1
      @width = canvas.right * @cell_w
      @height = canvas.top * @cell_h
      mw = RL.GetMonitorWidth(0)
      mh = RL.GetMonitorHeight(0)
      if mw > 0 && mh > 0
        maxw = mw * 0.92
        maxh = mh * 0.92
        if @width > maxw || @height > maxh
          s = maxw / @width.to_f
          s2 = maxh / @height.to_f
          s = s2 if s2 < s
          @font = (@font.to_f * s).to_i
          @font = 8 if @font < 8
          @cell_w = RL.rl_advance("█", @font)
          @cell_w = 1 if @cell_w < 1
          @cell_h = @font * 10 / 9
          @cell_h = 1 if @cell_h < 1
          @width = canvas.right * @cell_w
          @height = canvas.top * @cell_h
        end
      end
      @win_w = @width < 480 ? 480 : @width
      @win_h = @height < 300 ? 300 : @height
      RL.CloseWindow
      RL.ClearWindowState(RL::FLAG_WINDOW_HIDDEN)
      RL.InitWindow(@win_w, @win_h, "ttfx-rb (raylib)")
      load_font(font_path)
    end
    RL.SetTargetFPS(fps) unless fps == 0
    if fullscreen
      load_font(font_path)
      @cell_w = RL.rl_advance("█", @font)
      @cell_w = 1 if @cell_w < 1
      @width = canvas.right * @cell_w
      @height = canvas.top * @cell_h
    end
    STDERR.puts("font_ok=#{RL.rl_font_ok} cell=#{@cell_w}x#{@cell_h} canvas=#{canvas.right}x#{canvas.top} win=#{@win_w}x#{@win_h}")
    # The canvas is centered in the window via xpad/ypad.
    @xpad = (@win_w - @width) / 2
    @ypad = (@win_h - @height) / 2
  end

  # Monospace font with block-element coverage, first hit wins; "" keeps
  # raylib's default font (ASCII only).
  def load_font(font_path)
    unless font_path.nil? || font_path.empty?
      RL.rl_font_load(font_path)
      return if RL.rl_font_ok
    end
    home = ENV["HOME"] || ""
    cands = [
      home + "/Library/Fonts/FiraCodeNerdFontMono-Regular.ttf",
      home + "/Library/Fonts/HackNerdFontMono-Regular.ttf",
      home + "/Library/Fonts/FiraCodeNerdFontMono-Light.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
      home + "/.fonts/DejaVuSansMono.ttf"
    ]
    cands.each do |p|
      if File.exist?(p)
        RL.rl_font_load(p)
        return if RL.rl_font_ok
      end
    end
  end

  def window_open?
    !RL.WindowShouldClose && !RL.IsKeyPressed(RL::KEY_ESCAPE)
  end

  def close
    RL.CloseWindow
  end

  def draw_cells(cells)
    RL.BeginDrawing
    RL.rl_clear(BG)
    i = 0
    while i < cells.length
      c = cells[i]
      row = c[0]
      col = c[1]
      sym = c[2]
      if row >= 1 && row <= @canvas.top && col >= 1 && col <= @canvas.right
        packed = (255 << 24) | (c[5] << 16) | (c[4] << 8) | c[3]
        y = @ypad + (@canvas.top - row) * @cell_h + 1
        x = @xpad + (col - 1) * @cell_w + 2
        RL.rl_text_f(sym, x, y, @font, packed)
      end
      i += 1
    end
    RL.DrawFPS(10, 10) if @show_fps
    RL.EndDrawing
  end
end
