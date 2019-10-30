require 'curses'
require 'forwardable'


module CellState
  DEAD = 0
  ALIVE = 1
end


Vector2 = Struct.new(:x, :y) do
  def get(sym)
    send sym
  end

  def set(sym, val)
    send "#{sym}=", val
  end
end


class GameOfLifeGrid
  include Enumerable
  extend Forwardable

  attr_reader :grid, :dimensions
  def_delegators :@grid, :each, :[]

  def initialize(width, height)
    @dimensions = Vector2.new(width, height)
    @grid = new_grid(@dimensions)
  end

  def new_grid(dimensions)
    Array.new(dimensions.y) { Array.new(dimensions.x, CellState::DEAD) }
  end

  def advance
    new_grid = new_grid(@dimensions)
    new_grid.each_with_index do |line, y|
      line.each_with_index do |cell, x|
        neighborhood = get_neighborhood(x, y)
        sum = neighborhood.inject(:+)
        case sum
        when 3
          new_grid[y][x] = CellState::ALIVE
        when 4
          new_grid[y][x] = @grid[y][x]
        else
          new_grid[y][x] = CellState::DEAD
        end
      end
    end

    @grid = new_grid
  end

  def get_neighborhood(x, y)
    neighborhood = []

    (-1..1).each do |y_i|
      (-1..1).each do |x_i|
        neighborhood << @grid.fetch(y + y_i, []).fetch(x + x_i, CellState::DEAD)
      end
    end

    return neighborhood
  end
end


class GridWindow < Curses::Window
  attr_reader :grid, :grid_anchor, :cursor, :display_dimensions, :playing

  BOX_VERT_CHAR = '|'
  BOX_HORIZ_CHAR = '-'
  BOX_CORNER_CHAR = '*'
  DEAD_CELL_CHAR = '.'
  ALIVE_CELL_CHAR = '#'
  TIME_BETWEEN_UPDATES_S = 0.1

  def initialize(width, height, top, left, grid)
    super(height, width, top, left)
    self.keypad = true
    self.timeout = 0
    @grid = grid
    @grid_anchor = Vector2.new(0, 0)
    @display_dimensions = Vector2.new(maxx - 3, maxy - 3)
    @cursor = Vector2.new(display_dimensions.x / 2, display_dimensions.y / 2)
    @playing = false
  end

  def move_cursor(x, y)
    delta = Vector2.new(x, y)
    anchor_delta = Vector2.new(0, 0)

    [:x, :y].each do |sym|
      val = @cursor.get(sym) + delta.get(sym)
      clamped_val = val.clamp(0, @display_dimensions.get(sym))
      anchor_delta.set(sym, val - clamped_val)
      @cursor.set(sym, clamped_val)
    end

    move_anchor(anchor_delta.x, anchor_delta.y)
  end

  def move_anchor(x, y)
    delta = Vector2.new(x, y)

    [:x, :y].each do |sym|
      val = @grid_anchor.get(sym) + delta.get(sym)
      max_val = @grid.dimensions.get(sym) - @display_dimensions.get(sym) - 1
      @grid_anchor.set(sym, val.clamp(0, max_val))
    end
  end

  def draw_horiz_frame
    addch(BOX_CORNER_CHAR)
    (maxx - 2).times { addch(BOX_HORIZ_CHAR) }
    addch(BOX_CORNER_CHAR)
  end

  def toggle_cell
    x = @grid_anchor.x + @cursor.x
    y = @grid_anchor.y + @cursor.y
    @grid[y][x] = @grid[y][x] == CellState::ALIVE ? CellState::DEAD : CellState::ALIVE
  end

  def draw
    clear
    draw_horiz_frame

    @grid[@grid_anchor.y..@grid_anchor.y + @display_dimensions.y].each do |line|
      addch(BOX_VERT_CHAR)
      line[@grid_anchor.x..@grid_anchor.x + @display_dimensions.x].each do |cell|
        addch(cell == CellState::ALIVE ? ALIVE_CELL_CHAR : DEAD_CELL_CHAR)
      end
      addch(BOX_VERT_CHAR)
    end

    draw_horiz_frame
    setpos(@cursor.y + 1, @cursor.x + 1)
    refresh
  end

  def handle_input(ch)
    case ch
    when 'w'
      move_anchor(0, -1)
    when 's'
      move_anchor(0, 1)
    when 'a'
      move_anchor(-1, 0)
    when 'd'
      move_anchor(1, 0)
    when Curses::Key::UP
      move_cursor(0, -1)
    when Curses::Key::DOWN
      move_cursor(0, 1)
    when Curses::Key::LEFT
      move_cursor(-1, 0)
    when Curses::Key::RIGHT
      move_cursor(1, 0)
    when ' '
      toggle_cell
    when 'p'
      @playing = !@playing
    end
  end

  def loop
    draw

    last_update_time = 0
    while true
      updated = false

      while ch = get_char do
        return if ch == 'q'
        handle_input ch
        updated = true
      end

      time_since_update = Time.now - last_update_time
      if @playing and time_since_update.to_f > TIME_BETWEEN_UPDATES_S
        grid.advance
        last_update_time = Time.now
        updated = true
      end

      draw if updated
    end
  end
end


grid = GameOfLifeGrid.new(300, 300)

Curses.init_screen
Curses.noecho
Curses.cbreak
begin
  stdscr = Curses::stdscr
  win = GridWindow.new(stdscr.maxx / 2, stdscr.maxy / 2, 0, 0, grid)
  win.loop
ensure
  Curses.close_screen
end
