# Terminal size + ANSI screen control.
require "io/console"

module Terminal
  ANSI_CLEAR = "\e[2J"
  ANSI_HOME = "\e[H"
  ANSI_HIDE_CURSOR = "\e[?25l"
  ANSI_SHOW_CURSOR = "\e[?25h"

  def self.size
    rows = 24
    cols = 80
    begin
      io = $stdout
      ws = io.winsize
      rows = ws[0] if ws[0] > 0
      cols = ws[1] if ws[1] > 0
    rescue StandardError
      # not a tty (or winsize unavailable): keep the 80x24 default
    end
    [rows, cols]
  end
end
