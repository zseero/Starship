require 'rubygems'
require 'gosu'

module Layers
  Background, Plasma, EnemyShip, Ship, Cursor = *0...5
end

class Vector
  attr_accessor :x, :y
  def initialize(x, y); @x, @y = x, y; end
  def +(v); Vector.new(@x + v.x, @y + v.y); end
  def -(v); Vector.new(@x - v.x, @y - v.y); end
  def *(v); Vector.new(@x * v.x, @y * v.y); end
  def /(v); Vector.new(@x / v.x, @y / v.y); end
  def %(v); Vector.new(@x % v.x, @y % v.y); end
  def ==(v); (@x == v.x && @y == v.y); end
  def dup; Vector.new(@x, @y); end
end

class Window < Gosu::Window
  attr_accessor :starship
  attr_reader :screen_size, :half_screen_size, :world_size, :angle, :engagedCount, :engagedCountMax

  def initialize
    @screen_size = Vector.new(Gosu::screen_width, Gosu::screen_height)
    @half_screen_size = Vector.new(@screen_size.x / 2, @screen_size.y / 2)
    @world_size = Vector.new(2560, 1600)
    super(@screen_size.x, @screen_size.y, true)
    self.caption = "Starship"
    loadImages
    @angle = 0
    @engagedCount = 0
    @engagedCountMax = 3
    @starship = Starship.new(self)
    createEnemies(10)
  end

  def loadImages
    imgs = ['starship.png', 'space.jpg', 'target.png', 'plasma.png']
    $images = {}
    imgs.each do |img|
      $images[img.split('.')[0].to_sym] = Gosu::Image.new(self, 'lib/' + img, false)
    end
  end

  def createEnemies(i)
    @enemies = []
    i.times do
      @enemies << EnemyShip.new(self, Vector.new(@world_size.x / 2, @world_size.y / 2), 4)
    end
  end

  def update
    mouse = Vector.new(mouse_x, mouse_y)
    if mouse != @half_screen_size
      @angle = Gosu::angle(@starship.drawPos.x, @starship.drawPos.y, mouse.x, mouse.y).round
    end
    @starship.update
    count = 0
    @enemies.each {|enemy| enemy.update; count += 1 if enemy.engaged}
    @engagedCount = count
  end

  def draw
    backgroundPos = Vector.new(0, 0) - @starship.pos + @starship.drawPos
    imgSize = Vector.new($images[:space].width, $images[:space].height)
    backgroundPos %= imgSize
    $images[:space].draw(backgroundPos.x, backgroundPos.y, Layers::Background)
    $images[:space].draw(backgroundPos.x - imgSize.x, backgroundPos.y, Layers::Background)
    $images[:space].draw(backgroundPos.x, backgroundPos.y - imgSize.y, Layers::Background)
    $images[:space].draw(backgroundPos.x - imgSize.x, backgroundPos.y - imgSize.y, Layers::Background)
    targetSize = Vector.new(32, 32)
    $images[:target].draw(mouse_x - targetSize.x / 2, mouse_y - targetSize.x / 2, Layers::Cursor,
      targetSize.x.to_f / $images[:target].width.to_f,
      targetSize.y.to_f / $images[:target].height.to_f)
    @starship.draw
    @enemies.each {|enemy| enemy.draw}
  end

  def button_down(id)
    exit if id == Gosu::KbEscape
  end

  #def needs_cursor?; true; end
end

class Starship
  attr_reader :pos, :drawPos, :angle, :speed, :shipSize
  attr_accessor :window
  def initialize(window)
    @window = window
    @angle = @window.angle
    @pos = Vector.new(@window.world_size.x / 2, @window.world_size.y / 2)
    @oDrawPos = Vector.new(@window.half_screen_size.x, @window.half_screen_size.y)
    @drawPos = @oDrawPos.dup
    @shipSize = Vector.new(128, 32)
    @speed = 5
    @plasmas = []
  end

  def angleCalc
    newAngle = @window.angle
    dif = Gosu::angle_diff(@angle, newAngle).round
    if dif.abs > 2
      add = dif / dif.abs * 4 if dif != 0
      add = 0 if add.nil?
      @angle += add
      @angle %= 360
    end
  end

  def move
    oldPos = @pos.dup
    change = Vector.new(Gosu::offset_x(@angle, @speed), Gosu::offset_y(@angle, @speed))
    @pos += change
    xbool = @pos.x % @window.world_size.x != @pos.x
    ybool = @pos.y % @window.world_size.y != @pos.y
    @pos.x = oldPos.x if xbool
    @pos.y = oldPos.y if ybool
    @drawPos.x = @pos.x if @pos.x < @oDrawPos.x
    @drawPos.y = @pos.y if @pos.y < @oDrawPos.y
    difToEnd = @window.world_size - @pos
    @drawPos.x = (@oDrawPos.x * 2) - difToEnd.x if difToEnd.x < @oDrawPos.x
    @drawPos.y = (@oDrawPos.y * 2) - difToEnd.y if difToEnd.y < @oDrawPos.y
  end

  def fire
    @plasma.fire
    @plasmas << @plasma
    @plasma = nil
  end

  def update
    angleCalc
    move
    if @window.button_down?(Gosu::MsLeft) && @plasma.nil?
      @plasma = PlasmaBall.new(self, Vector.new((@shipSize.x * 0.7).round, 0))
    end
    fire if @plasma && !@window.button_down?(Gosu::MsLeft)
    @plasma.update if @plasma
    @plasmas.each {|plasma| plasma.update}
    @plasmas.delete_if {|plasma| plasma.old?}
  end

  def draw
    $images[:starship].draw_rot(@drawPos.x, @drawPos.y, Layers::Ship, (@angle - 90) % 360,
      0.5, 0.5, @shipSize.x.to_f / $images[:starship].width.to_f,
      @shipSize.y.to_f / $images[:starship].height.to_f)
    @plasma.draw if @plasma
    @plasmas.each {|plasma| plasma.draw}
  end
end

class EnemyShip
  attr_reader :pos, :angle, :speed, :shipSize, :engaged
  attr_accessor :window
  def initialize(window, pos, speed, smartness = Random.rand(0..2))
    @window, @pos, @speed, @smartness = window, pos, speed, smartness
    @angle = 90
    @drawPos = Vector.new(-100, -100)
    @shipSize = @window.starship.shipSize.dup
    @plasmas = []
    @counter = 0
    @tooClose = 100
    @inRange = 1000
    findNewAngle
  end

  def angleCalc
    dif = Gosu::angle_diff(@angle, @newAngle).round
    if dif.abs > 1
      add = dif / dif.abs * 2 if dif != 0
      add = 0 if add.nil?
      @angle += add
      @angle %= 360
    end
  end

  def move
    oldPos = @pos.dup
    change = Vector.new(Gosu::offset_x(@angle, @speed), Gosu::offset_y(@angle, @speed))
    @pos += change
    xbool = @pos.x % @window.world_size.x != @pos.x
    ybool = @pos.y % @window.world_size.y != @pos.y
    @pos.x = oldPos.x if xbool
    @pos.y = oldPos.y if ybool
    if xbool || ybool
      @newAngle = Gosu::angle(@pos.x, @pos.y, @window.world_size.x / 2, @window.world_size.y / 2)
      random = 20
      @newAngle += Random.rand((random * -1)..random)
      @newAngle %= 360
    end
  end

  def findNewAngle
    angleChance = 90; distChance = 2000
    angle = Random.rand(0...360)
    dist = Random.rand((distChance * -1)..distChance)
    dest = @window.starship.pos + Vector.new(Gosu::offset_x(angle, dist), Gosu::offset_y(angle, dist))
    if Gosu::distance(@pos.x, @pos.y, @window.starship.pos.x, @window.starship.pos.y) < @inRange
      if @window.engagedCount < @window.engagedCountMax || @engaged
        @engaged = true
        @newAngle = Gosu::angle(@pos.x, @pos.y, dest.x, dest.y)
      end
    else
      @engaged = false
      @newAngle = Random.rand(0...360)
    end
  end

  def runAway
    if Gosu::distance(@pos.x, @pos.y, @window.starship.pos.x, @window.starship.pos.y) < @tooClose
      @newAngle = Gosu::angle(@pos.x, @pos.y, @window.starship.pos.x, @window.starship.pos.y) + 180
      @newAngle %= 360
    end
  end

  def shoot?
    requiredAngle = Gosu::angle(@pos.x, @pos.y, @window.starship.pos.x, @window.starship.pos.y)
    dist = Gosu::distance(@pos.x, @pos.y, @window.starship.pos.x, @window.starship.pos.y)
    (Gosu::angle_diff(@angle, requiredAngle).abs < 10 && dist < @inRange) || dist < @tooClose
  end

  def startCharging?
    requiredAngle = Gosu::angle(@pos.x, @pos.y, @window.starship.pos.x, @window.starship.pos.y)
    dist = Gosu::distance(@pos.x, @pos.y, @window.starship.pos.x, @window.starship.pos.y)
    dif = Gosu::angle_diff(@angle, requiredAngle)
    dist < @inRange && dif.abs < 20 || dist < 200
  end

  def fire
    @plasma.fire
    @plasmas << @plasma
    @plasma = nil
  end

  def update
    findNewAngle if @counter % 60 == 0
    runAway
    angleCalc
    move
    if @plasma.nil? && @counter % 30 == 0 && startCharging?
      @plasma = PlasmaBall.new(self, Vector.new((@shipSize.x * 0.7).round, 0))
    end
    fire if @plasma && shoot? && @counter % 20 == 0
    @plasma.update if @plasma
    @plasmas.each {|plasma| plasma.update}
    @plasmas.delete_if {|plasma| plasma.old?}
    @drawPos = @pos - @window.starship.pos + @window.starship.drawPos
    @counter += 1
  end

  def draw
    $images[:starship].draw_rot(@drawPos.x, @drawPos.y, Layers::EnemyShip, (@angle - 90) % 360,
      0.5, 0.5, @shipSize.x.to_f / $images[:starship].width.to_f,
      @shipSize.y.to_f / $images[:starship].height.to_f)
    @plasma.draw if @plasma
    @plasmas.each {|plasma| plasma.draw}
  end
end

class PlasmaBall
  def initialize(ship, posModify)
    @stage = :charging
    @ship = ship
    @radius = 10
    @radiusMax = 40
    getModify(posModify)
    posGetFromShip
    @rotateAngle = 0
    @distanceTravelled = 0
  end

  def old?
    @distanceTravelled > 10000
  end

  def fire
    @stage = :fired
    @angle = @ship.angle
    @speed = @ship.speed * 2
  end

  def getModify(posModify)
    @modifyAngle = Gosu::angle(0, 0, posModify.x, posModify.y) - 90
    @modifyDist = Gosu::distance(0, 0, posModify.x, posModify.y)
  end

  def posGetFromShip
    angle = (@ship.angle + @modifyAngle) % 360
    modify = Vector.new( Gosu::offset_x(angle, @modifyDist), Gosu::offset_y(angle, @modifyDist) )
    @pos = @ship.pos + modify
  end

  def update
    posGetFromShip if @stage == :charging
    @radius += 0.2 if @stage == :charging && @radius < @radiusMax
    @rotateAngle += 2; @rotateAngle %= 360
    if @stage == :fired
      @pos += Vector.new(Gosu::offset_x(@angle, @speed), Gosu::offset_y(@angle, @speed))
      @distanceTravelled += @speed
    end
    @ship.fire if @radius >= @radiusMax && @stage == :charging
    @drawPos = @pos - @ship.window.starship.pos + @ship.window.starship.drawPos
  end

  def draw
    $images[:plasma].draw_rot(@drawPos.x, @drawPos.y, Layers::Plasma, @rotateAngle, 0.5, 0.5,
      (@radius * 2.0) / $images[:plasma].width, (@radius * 2.0) / $images[:plasma].height)
  end
end

window = Window.new
window.show