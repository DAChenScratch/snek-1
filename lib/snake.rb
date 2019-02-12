ACTIONS = [:up, :down, :left, :right]

class Point
  attr_reader :x, :y

  def initialize(data, y=nil)
    if y
      @x = data
      @y = y
    else
      @x = data['x']
      @y = data['y']
    end
  end

  def move(direction)
    case direction
    when :up
      Point.new(x, y-1)
    when :down
      Point.new(x, y+1)
    when :left
      Point.new(x-1, y)
    when :right
      Point.new(x+1, y)
    end
  end

  def ==(other)
    x == other.x && y == other.y
  end

  def hash
    [x, y].hash
  end

  def inspect
    "(#{x}, #{y})"
  end
end

require "securerandom"

class Snake
  attr_reader :id, :health, :body
  attr_writer :health

  def initialize(id: nil, health: 100, body: [])
    @id = id || SecureRandom.hex
    @health = health
    @body = body
  end

  def self.from_json(data)
    new(
      id: data['id'],
      health: data['health'],
      body: data['body'].map { |p| Point.new(p) }
    )
  end

  def initialize_copy(other)
    super(other)

    @body = @body.dup
  end

  def alive?
    health > 0
  end

  def head
    @body[0]
  end

  def tail
    @body.reject { |x| x == head }
  end

  def length
    @body.length
  end

  def die!
    @health = 0
  end

  def simulate!(action, game)
    board = game.board

    point = head.move(action)

    @body.unshift(point)

    self
  end

  def hash
    id.hash
  end

  def ==(other)
    id == other.id
  end
end

class Grid
  attr_reader :width, :height

  def initialize(width, height)
    @width = width
    @height = height
    @grid = Array.new(width * height)
  end

  def get(x, y=nil)
    unless y
      y = x.y
      x = x.x
    end
    return nil if x < 0 || y < 0 || x >= @width || y >= @height
    @grid[y * @width + x]
  end
  alias_method :at, :get

  def set(x, y, value=nil)
    unless value
      value = y
      y = x.y
      x = x.x
    end
    raise if x < 0 || y < 0 || x >= @width || y >= @height
    @grid[y * @width + x] = value
  end

  def set_all(points, value)
    points.each do |point|
      self.set(point, value)
    end
  end

  def inspect
    values = @grid.map(&:inspect)
    hsize = values.map(&:size).max + 1
    values.map! { |v| v.ljust(hsize) }
    "#<Grid #{@width}x#{@height}\n" + values.each_slice(@width).map(&:join).join("\n") + "\n>"
  end
end

class Board
  attr_reader :snakes, :width, :height, :food

  def initialize(data)
    @width = data['width']
    @height = data['height']
    @snakes = data['snakes'].map { |s| Snake.new(s) }
    @food = data['food'].map { |f| Point.new(f) }
  end

  def initialize_copy(other)
    super(other)

    @snakes = @snakes.map(&:dup)
    @food = @food.map(&:dup)
  end

  def new_grid
    Grid.new(@width, @height)
  end

  def out_of_bounds?(x, y=nil)
    unless y
      y = x.y
      x = x.x
    end
    x < 0 || y < 0 || x >= @width || y >= @height
  end
end

class Game
  attr_reader :id, :turn, :self_id, :board

  def initialize(data)
    @id = data['game']['id']
    @turn = data['turn']
    @self_id = data['you']['id']
    @board = Board.new(data['board'])
  end

  def initialize_copy(other)
    super(other)
    @board = @board.dup
  end

  def snakes
    @board.snakes
  end

  def player
    snakes.detect { |s| s.id == @self_id }
  end

  def enemies
    snakes - [player]
  end

  def simulate(actions)
    game = dup
    game.simulate!(actions)
    game
  end

  def simulate!(actions)
    snakes = board.snakes.select(&:alive?)

    snakes.each do |snake|
      action = actions[snake.id]
      next unless action

      snake.simulate!(action, self)
    end

    snakes.each do |snake|
      snake.health -= 1
    end

    snakes.each do |snake|
      if board.food.include?(snake.head)
        board.food.delete(snake.head)
      elsif actions[snake.id]
        snake.body.pop
      else
        # We didn't simulate a move
      end
    end

    heads = snakes.group_by(&:head)
    walls = Grid.new(board.width, board.height)
    snakes.each do |snake|
      walls.set_all(snake.tail, true)
    end

    snakes.each do |snake|
      if board.out_of_bounds?(snake.head)
        snake.die!
        break
      end

      if walls.at(snake.head)
        snake.die!
        break
      end

      lost_collision =
        heads[snake.head].any? do |other|
          next if other.equal?(snake)

          other.length >= snake.length
        end

      if lost_collision
        snake.die!
        break
      end
    end
  end
end

class BoardBFS
  attr_reader :game, :board

  attr_reader :voronoi_tiles
  attr_reader :distance_to_food

  def initialize(game)
    @game = game
    @board = game.board

    @voronoi_tiles = Hash.new(0)
    @distance_to_food = {}

    calculate
  end

  def calculate
    visited = Grid.new(board.width, board.height)
    food = Grid.new(board.width, board.height)

    next_queue = []

    food.set_all(board.food, true)

    @game.snakes.each do |snake|
      next_queue << [snake.head.x, snake.head.y, snake]

      snake.tail.each do |point|
        visited.set(point, true)
      end
    end

    distance = 0
    until next_queue.empty?
      queue = next_queue
      next_queue = []

      queue.each do |x, y, snake|
        next if board.out_of_bounds?(x, y)
        next if visited.at(x,y)
        visited.set(x, y, true)

        @voronoi_tiles[snake] += 1

        if food.at(x,y)
          @distance_to_food[snake] ||= distance
        end

        next_queue << [x+1, y, snake]
        next_queue << [x-1, y, snake]
        next_queue << [x, y+1, snake]
        next_queue << [x, y-1, snake]
      end

      distance += 1
    end
  end
end

class GameScorer
  def initialize(game, bfs: nil)
    @game = game
    @bfs = bfs || BoardBFS.new(@game)
  end

  def score
    player = @game.player
    return -999999 unless player.alive?

    enemies = @game.enemies.select(&:alive?)

    [
        25 * player.length,
         1 * player.health,
      -100 * enemies.count,
        -1 * (enemies.map(&:length).max || 0),
        -1 * enemies.sum(&:length),

         1 * @bfs.voronoi_tiles[player],
        -1 * (@bfs.distance_to_food[player] || @game.board.width),
    ].sum
  end
end

class MoveDecider
  attr_reader :game, :board

  def initialize(game)
    @game = game
    @board = game.board

    @walls = board.new_grid
    @snakes = @game.snakes.select(&:alive?)
    @snakes.each do |snake|
      @walls.set_all(snake.body, true)
    end
  end

  def next_move
    reasonable_moves = Hash[
      @snakes.map do |snake|
        moves = ACTIONS.reject do |move|
          head = snake.head
          new_head = head.move(move)

          board.out_of_bounds?(new_head) || @walls.at(new_head)
        end

        [snake, moves]
      end
    ]

    ACTIONS.max_by do |action|
      game = @game.simulate({
        @game.player.id => action
      })

      score = GameScorer.new(game).score
      pp(action: action, player: game.player, score: score)

      score
    end
  end
end

