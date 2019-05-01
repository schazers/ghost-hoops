if CASTLE_PREFETCH then
  CASTLE_PREFETCH({
    'img/ball.png',
    'img/hoop.png',
    'img/flash.png',
    'sfx/aim.wav',
    'sfx/power.wav',
    'sfx/shoot.wav',
    'sfx/bounce.wav',
    'sfx/flash.wav',
  })
end

-- Render constants
local GAME_WIDTH = 192
local GAME_HEIGHT = 192
local RENDER_SCALE = 3
local DRAW_PHYSICS_OBJECTS = false
local GHOST_RECORD_INTERVAL = 0.1

-- Game constants
local SHOT_X = 25
local SHOT_Y = 140
local BALL_BOUNCINESS = 0.7
local GRAVITY = 200
local GAME_SECONDS = 30

-- Game variables
local world
local ball
local hoop
local backboard
local flashes
local shotStep
local shotTimer
local shotAngle
local shotPower
local celebrationTimer
local gameTimer
local numShotsMade
local gameState
local opponentGhost
local currOpponentGhostFrame
local opponentUser
local playerGhost
local playerGhostRecordingTimer

-- Assets
local ballImage
local hoopImage
local flashImage
local aimSound
local powerSound
local shootSound
local bounceSound
local flashSound

-- Initializes the game
function love.load()
  -- Load assets
  ballImage = love.graphics.newImage('img/ball.png')
  hoopImage = love.graphics.newImage('img/hoop.png')
  flashImage = love.graphics.newImage('img/flash.png')
  ballImage:setFilter('nearest', 'nearest')
  hoopImage:setFilter('nearest', 'nearest')
  flashImage:setFilter('nearest', 'nearest')
  aimSound = love.audio.newSource('sfx/aim.wav', 'static')
  powerSound = love.audio.newSource('sfx/power.wav', 'static')
  shootSound = love.audio.newSource('sfx/shoot.wav', 'static')
  bounceSound = love.audio.newSource('sfx/bounce.wav', 'static')
  flashSound = love.audio.newSource('sfx/flash.wav', 'static')

  -- Initialize game variables
  shotStep = 'aim'
  shotTimer = 0.00
  shotAngle = 0
  shotPower = 0
  celebrationTimer = 0.00

  -- Set up the physics world
  love.physics.setMeter(10)
  world = love.physics.newWorld(0, GRAVITY, true)
  world:setCallbacks(onCollide)
 
  -- Create the ball
  ball = createCircle(SHOT_X, SHOT_Y, 8)
  ball.fixture:setRestitution(BALL_BOUNCINESS)

  -- Create the hoop (it's actually just two static circles, one for each side of the hoop)
  hoop = {
    createCircle(139, 82, 2, true),
    createCircle(163, 82, 2, true)
  }

  -- Create the backboard
  backboard = createRectangle(170, 65, 5, 50, true)

  -- Create an empty array for camera flashes
  flashes = {}

  gameState = 'title'
end

-- open a ghost, if one exists
function castle.postopened(post)
  opponentGhost = post.data
  if post.creator ~= nil then
    opponentUser = post.creator
  end
end

function restartGame()
  gameTimer = GAME_SECONDS
  numShotsMade = 0
  playerGhost = {}
  playerGhost['ballData'] = {}
  playerGhostRecordingTimer = GHOST_RECORD_INTERVAL
  currOpponentGhostFrame = nil
  gameState = 'playing'
end

-- Updates the game state
function love.update(dt)
  if gameState == 'playing' then
    if gameTimer < 0 and shotStep ~= 'shoot' then
      -- Save one last frame of ghost
      playerGhost['ballData'][#playerGhost + 1] = {
        t = gameTimer,
        x = ball.body:getX(),
        y = ball.body:getY(),
      }
      playerGhost['numShots'] = numShotsMade
      gameState = 'score_screen'
    else
      -- Update timers
      shotTimer = shotTimer + dt
      celebrationTimer = math.max(0.00, celebrationTimer - dt)
      gameTimer = gameTimer - dt
      playerGhostRecordingTimer = playerGhostRecordingTimer + dt

      -- Record player's ghost
      if playerGhostRecordingTimer > GHOST_RECORD_INTERVAL then
        playerGhost['ballData'][#playerGhost + 1] = {
          t = gameTimer,
          x = ball.body:getX(),
          y = ball.body:getY(),
        }
        playerGhostRecordingTimer = 0.0
      end

      -- Get current frame of opponent's ghost
      if opponentGhost ~= nil then
        for i,v in ipairs(opponentGhost['ballData']) do
          if opponentGhost['ballData'][i].t < gameTimer then
            currOpponentGhostFrame = opponentGhost['ballData'][i]
          end
        end
      end

      -- Update the physics simulation
      world:update(dt)

      -- Aim the ball and select power
      local t = shotTimer % 2.00
      if shotStep == 'aim' then
        if t < 1.00 then
          shotAngle = -t * math.pi / 2
        else
          shotAngle = (t - 2.00) * math.pi / 2
        end
      elseif shotStep == 'power' then
        if t < 1.00 then
          shotPower = t
        else
          shotPower = 2.00 - t
        end
      end

      -- Keep the ball in one place until it's been shot
      if shotStep ~= 'shoot' then
        ball.body:setPosition(SHOT_X, SHOT_Y)
        ball.body:setLinearVelocity(0, 0)
      end

      -- Check for baskets
      local dx = ball.body:getX() - (hoop[1].body:getX() + hoop[2].body:getX()) / 2
      local dy = ball.body:getY() - (hoop[1].body:getY() + hoop[2].body:getY()) / 2
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist < 3 and celebrationTimer <= 0.00 then
        numShotsMade = numShotsMade + 1
        celebrationTimer = 1.00
        love.audio.play(flashSound:clone())
      end

      -- Camera flashes!
      if celebrationTimer > 0.00 then
        for _, flash in ipairs(flashes) do
          flash.timeToDisappear = math.max(0.00, flash.timeToDisappear - dt)
        end
        table.insert(flashes, {
          x = math.random(10, GAME_WIDTH - 10),
          y = math.random(10, GAME_HEIGHT - 10),
          timeToDisappear = 0.10
        })
      else
        flashes = {}
      end

      -- Reset shot if ball is off bottom
      if shotStep == 'shoot' and ball.body:getY() > GAME_HEIGHT * 1.35 then
        love.audio.play(aimSound:clone())
        shotAngle = 0
        shotPower = 0
        shotStep = 'aim'
      end
    end
  end
end

-- Renders the game
function love.draw()
  -- Scale and crop the screen
  love.graphics.setScissor(0, 0, RENDER_SCALE * GAME_WIDTH, RENDER_SCALE * GAME_HEIGHT)
  love.graphics.scale(RENDER_SCALE, RENDER_SCALE)
  if celebrationTimer > 0.00 then
    love.graphics.clear(253 / 255, 217 / 255, 37 / 255)
  else
    love.graphics.clear(252 / 255, 147 / 255, 1 / 255)
  end
  love.graphics.setColor(1, 1, 1)

  if gameState == 'title' then
    love.graphics.print('Press Space to start hoopin', 32, 98, 0, 0.8, 0.8)
  elseif gameState == 'score_screen' then
    love.graphics.print('Hoops scored: '..numShotsMade, 32, 98, 0, 0.8, 0.8)
    love.graphics.print('Press Space to re-hoop', 32, 118, 0, 0.8, 0.8)
    love.graphics.print('Press p to post a ghost', 32, 138, 0, 0.8, 0.8)
  elseif gameState == 'playing' then
    -- Draw the camera flashes
    for _, flash in ipairs(flashes) do
      if flash.timeToDisappear > 0.00 then
        love.graphics.draw(flashImage, flash.x - 5, flash.y - 7)
      end
    end

    local secondsFormat = gameTimer < 10.0 and "%01d" or "%02d"
    love.graphics.print(string.format(secondsFormat, math.max(gameTimer + 1, 0)), 2, 2, 0, 1.0, 1.0)

    -- Draw the ball
    love.graphics.draw(ballImage, ball.body:getX() - 8, ball.body:getY() - 8)

    -- Draw the ghost ball
    if currOpponentGhostFrame ~= nil then
      local x,y = currOpponentGhostFrame.x, currOpponentGhostFrame.y
      love.graphics.setColor(1,1,1,0.4)
      love.graphics.draw(ballImage, x - 8, y - 8)
    end

    love.graphics.setColor(1,1,1,1)

    -- Draw the hoop
    love.graphics.draw(hoopImage, 138, 40)

    -- Draw aiming reticle
    if shotStep ~= 'shoot' then
      love.graphics.setColor(91 / 255, 20 / 255, 3 / 255)
      local increment = 5 + 8 * shotPower
      for dist = 8 + increment, 8 + 5 * increment, increment do
        love.graphics.rectangle('fill', SHOT_X + math.cos(shotAngle) * dist - 1, SHOT_Y + math.sin(shotAngle) * dist - 1, 2, 2)
      end
    end

    -- Draw the physics objects (for debugging)
    if DRAW_PHYSICS_OBJECTS then
      love.graphics.setColor(1, 1, 1)
      love.graphics.circle('fill', ball.body:getX(), ball.body:getY(), ball.shape:getRadius())
      love.graphics.circle('fill', hoop[1].body:getX(), hoop[1].body:getY(), hoop[1].shape:getRadius())
      love.graphics.circle('fill', hoop[2].body:getX(), hoop[2].body:getY(), hoop[2].shape:getRadius())
      love.graphics.polygon('fill', backboard.body:getWorldPoints(backboard.shape:getPoints()))
    end
  end
end

-- Shoot the ball by pressing space
function love.keypressed(key)
  if key == 'r' and gameState == 'playing' then
    restartGame()
  elseif key == 'p' and gameState == 'score_screen' then
    -- Make a post
    network.async(function()
      castle.post.create {
        message = 'I dare thee to out-hoop me.',
        media = 'capture',
        data = playerGhost,
      }
    end)
  elseif key == 'space' then
    if gameState == 'title' or gameState == 'score_screen' then
      restartGame()
    elseif gameState == 'playing' then
      shotTimer = 0.00
      -- Go from aiming to selecting power
      if shotStep == 'aim' then
        shotStep = 'power'
        love.audio.play(powerSound:clone())
      -- Go from selecting power to shooting the ball
      elseif shotStep == 'power' then
        shotStep = 'shoot'
        love.audio.play(shootSound:clone())
        local speed = 180 * shotPower + 120
        ball.body:setLinearVelocity(speed * math.cos(shotAngle), speed * math.sin(shotAngle))
      end
    end
  end
end

-- Play a sound when there's a collision
function onCollide()
  love.audio.play(bounceSound:clone())
end

-- Creates a new physics object that's just a 2D circle
function createCircle(x, y, radius, isStatic)
  -- Create the physics objects
  local body = love.physics.newBody(world, x, y, isStatic and 'static' or 'dynamic')
  local shape = love.physics.newCircleShape(radius)
  local fixture = love.physics.newFixture(body, shape, 1)
  -- Return the circle
  return { body = body, shape = shape, fixture = fixture }
end

-- Creates a new physics object that's just a 2D rectangle
function createRectangle(x, y, width, height, isStatic)
  -- Create the physics objects
  local body = love.physics.newBody(world, x, y, isStatic and 'static' or 'dynamic')
  local shape = love.physics.newRectangleShape(width, height)
  local fixture = love.physics.newFixture(body, shape, 1)
  -- Return the rectangle
  return { body = body, shape = shape, fixture = fixture }
end
