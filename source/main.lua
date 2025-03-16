-- FlappyDate: Actor-Based Flappy Bird Clone for Playdate
-- main.lua

import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/ui"
import "CoreLibs/object"
import "CoreLibs/crank"
import "CoreLibs/keyboard"

import "events"
import "actor"
import "component"
import "world"
import "components/transform"
import "components/physics"
import "system"


-- Add extra imports for sound if we decide to use it later
-- import "CoreLibs/sound"

-- Engine Constants
local gfx <const> = playdate.graphics
local geom <const> = playdate.geometry

-- Game Constants
local GRAVITY = 0.5
local JUMP_FORCE = -7
local PIPE_SPEED = 2
local PIPE_WIDTH = 40
local PIPE_GAP = 100
local PIPE_SPAWN_TIME = 2000 -- milliseconds
local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240



class('BirdComponent').extends(Component)

function BirdComponent:init(actor)
    BirdComponent.super.init(self, actor)
    self.passedPipes = {}
end

function BirdComponent:update()
    local physics = self.actor:getComponent(PhysicsComponent)
    local transform = self.actor:getComponent(TransformComponent)

    if playdate.buttonJustPressed(playdate.kButtonA) then
        physics:setVelocity(nil, JUMP_FORCE)
        EventSystem.emit("birdFlap")
    end

    -- Update rotation based on velocity
    transform:setRotation(math.min(math.max(-30, physics.velocity.y * 3), 90))

    -- Check boundaries
    if transform.y < 0 or transform.y > SCREEN_HEIGHT then
        EventSystem.emit("gameOver")
    end

    -- Store the bird position and rotation for direct drawing
    _G.birdForDrawing = {
        x = transform.x,
        y = transform.y,
        rotation = transform.rotation
    }
end

-- This will be called from playdate.update
function drawBird()
    if _G.birdForDrawing and _G.gameStateForDrawing == "playing" then
        -- Draw the bird directly
        local bird = _G.birdForDrawing
        gfx.setColor(gfx.kColorBlack)

        -- Draw bird body
        gfx.fillCircleAtPoint(bird.x, bird.y, 12)

        -- Draw beak
        gfx.fillTriangle(
            bird.x + 8, bird.y - 2,
            bird.x + 16, bird.y,
            bird.x + 8, bird.y + 2
        )

        -- Draw eye
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(bird.x + 4, bird.y - 3, 3)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(bird.x + 5, bird.y - 3, 1)

        -- Draw wing
        gfx.drawLine(bird.x - 6, bird.y + 2, bird.x - 10, bird.y + 8)
        gfx.drawLine(bird.x - 10, bird.y + 8, bird.x, bird.y + 6)
    end
end

class('PipeComponent').extends(Component)

function PipeComponent:init(actor, gapY)
    PipeComponent.super.init(self, actor)
    self.gapY = gapY
    self.width = PIPE_WIDTH
    self.gap = PIPE_GAP
    self.passed = false

    -- Create pipe images
    self:createPipeSprites()
end

function PipeComponent:createPipeSprites()
    -- Create top pipe
    local topPipeImage = gfx.image.new(self.width, self.gapY - self.gap / 2)
    gfx.pushContext(topPipeImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, self.width, self.gapY - self.gap / 2)
    gfx.popContext()

    -- Create bottom pipe
    local bottomPipeImage = gfx.image.new(self.width, SCREEN_HEIGHT - (self.gapY + self.gap / 2))
    gfx.pushContext(bottomPipeImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, self.width, SCREEN_HEIGHT - (self.gapY + self.gap / 2))
    gfx.popContext()

    -- Create and position the sprites
    self.topPipe = gfx.sprite.new(topPipeImage)
    self.topPipe:moveTo(self.actor:getComponent(TransformComponent).x, (self.gapY - self.gap / 2) / 2)
    self.topPipe:setZIndex(20)
    self.topPipe:add()
    print("Top pipe sprite added")

    self.bottomPipe = gfx.sprite.new(bottomPipeImage)
    self.bottomPipe:moveTo(self.actor:getComponent(TransformComponent).x,
        self.gapY + self.gap / 2 + (SCREEN_HEIGHT - (self.gapY + self.gap / 2)) / 2)
    self.bottomPipe:setZIndex(20)
    self.bottomPipe:add()
    print("Bottom pipe sprite added")
end

function PipeComponent:update()
    local transform = self.actor:getComponent(TransformComponent)

    -- Move pipes
    self.topPipe:moveTo(transform.x, self.topPipe.y)
    self.bottomPipe:moveTo(transform.x, self.bottomPipe.y)

    -- Store pipe data for direct drawing
    if not _G.pipesForDrawing then
        _G.pipesForDrawing = {}
    end

    -- Keep track of this pipe
    local pipeData = {
        x = transform.x,
        gapY = self.gapY,
        width = self.width,
        gap = self.gap
    }

    -- Store in global table, using the actor ID as key
    _G.pipesForDrawing[self.actor.id] = pipeData
end

-- This will be called from playdate.update
function drawPipes()
    if _G.pipesForDrawing and _G.gameStateForDrawing == "playing" then
        gfx.setColor(gfx.kColorBlack)

        -- Count active pipes
        local pipeCount = 0

        -- Draw all pipes
        for id, pipe in pairs(_G.pipesForDrawing) do
            pipeCount = pipeCount + 1

            -- Top pipe
            local topHeight = pipe.gapY - pipe.gap / 2
            gfx.fillRect(pipe.x - pipe.width / 2, 0, pipe.width, topHeight)

            -- Bottom pipe
            local bottomY = pipe.gapY + pipe.gap / 2
            gfx.fillRect(pipe.x - pipe.width / 2, bottomY, pipe.width, SCREEN_HEIGHT - bottomY)
        end

        -- Debug pipe count
        gfx.drawText("Pipes: " .. pipeCount, 300, 5)
    end
end

function PipeComponent:onRemove()
    self.topPipe:remove()
    self.bottomPipe:remove()

    -- Also remove from the drawing table when the pipe is removed
    if _G.pipesForDrawing and _G.pipesForDrawing[self.actor.id] then
        _G.pipesForDrawing[self.actor.id] = nil
        print("Removed pipe from drawing: " .. self.actor.id)
    end
end

class('ScoreComponent').extends(Component)

function ScoreComponent:init(actor)
    ScoreComponent.super.init(self, actor)
    self.score = 0
end

function ScoreComponent:incrementScore()
    self.score = self.score + 1
    EventSystem.emit("scoreChanged", self.score)
end

-- ==========================================
-- Game-Specific Systems
-- ==========================================
class('InputSystem').extends(System)

function InputSystem:update()
    if not self.world.active then
        if playdate.buttonJustPressed(playdate.kButtonA) then
            EventSystem.emit("startGame")
        end
    end
end

class('MovementSystem').extends(System)

function MovementSystem:update()
    local pipes = self.world:getActorsWithTag("pipe")

    for _, pipe in ipairs(pipes) do
        local transform = pipe:getComponent(TransformComponent)
        transform:setPosition(transform.x - PIPE_SPEED, transform.y)

        -- Remove pipe if off screen
        if transform.x < -PIPE_WIDTH / 2 then
            self.world:removeActor(pipe)
        end
    end
end

class('CollisionSystem').extends(System)

function CollisionSystem:update()
    local birds = self.world:getActorsWithTag("bird")
    local pipes = self.world:getActorsWithTag("pipe")

    for _, bird in ipairs(birds) do
        local birdTransform = bird:getComponent(TransformComponent)
        local birdPhysics = bird:getComponent(PhysicsComponent)
        local birdComponent = bird:getComponent(BirdComponent)

        for _, pipe in ipairs(pipes) do
            local pipeTransform = pipe:getComponent(TransformComponent)
            local pipeComponent = pipe:getComponent(PipeComponent)

            -- Collision check
            if self:checkCollision(bird, pipe) then
                EventSystem.emit("gameOver")
                return
            end

            -- Score check
            if not pipeComponent.passed and birdTransform.x > pipeTransform.x + pipeComponent.width / 2 then
                pipeComponent.passed = true
                self.world:getActorsWithComponent(ScoreComponent)[1]:getComponent(ScoreComponent):incrementScore()
            end
        end
    end
end

function CollisionSystem:checkCollision(bird, pipe)
    local birdTransform = bird:getComponent(TransformComponent)
    local birdPhysics = bird:getComponent(PhysicsComponent)
    local pipeTransform = pipe:getComponent(TransformComponent)
    local pipeComponent = pipe:getComponent(PipeComponent)

    local birdLeft = birdTransform.x - birdPhysics.width / 2
    local birdRight = birdTransform.x + birdPhysics.width / 2
    local birdTop = birdTransform.y - birdPhysics.height / 2
    local birdBottom = birdTransform.y + birdPhysics.height / 2

    local pipeLeft = pipeTransform.x - pipeComponent.width / 2
    local pipeRight = pipeTransform.x + pipeComponent.width / 2

    local topPipeBottom = pipeComponent.gapY - pipeComponent.gap / 2
    local bottomPipeTop = pipeComponent.gapY + pipeComponent.gap / 2

    -- Check collision with top pipe
    if birdRight > pipeLeft and birdLeft < pipeRight and birdTop < topPipeBottom then
        return true
    end

    -- Check collision with bottom pipe
    if birdRight > pipeLeft and birdLeft < pipeRight and birdBottom > bottomPipeTop then
        return true
    end

    return false
end

class('PipeSpawnSystem').extends(System)

function PipeSpawnSystem:init(world)
    PipeSpawnSystem.super.init(self, world)
    self.spawnTimer = nil
end

function PipeSpawnSystem:startSpawning()
    self:spawnPipe()
    self.spawnTimer = playdate.timer.performAfterDelay(PIPE_SPAWN_TIME, function()
        self:spawnPipe()
    end)
end

function PipeSpawnSystem:spawnPipe()
    if not self.world.active then return end

    local gapY = math.random(80, SCREEN_HEIGHT - 80)

    local pipe = Actor()
    pipe:addComponent(TransformComponent, SCREEN_WIDTH + PIPE_WIDTH / 2, SCREEN_HEIGHT / 2)
    pipe:addComponent(PipeComponent, gapY)
    pipe:addTag("pipe")

    self.world:addActor(pipe)

    self.spawnTimer = playdate.timer.performAfterDelay(PIPE_SPAWN_TIME, function()
        self:spawnPipe()
    end)
end

function PipeSpawnSystem:stopSpawning()
    if self.spawnTimer then
        self.spawnTimer:remove()
        self.spawnTimer = nil
    end
end

class('UISystem').extends(System)

function UISystem:init(world)
    UISystem.super.init(self, world)
    self.score = 0
    self.gameState = "title" -- title, playing, gameOver

    EventSystem.subscribe("scoreChanged", function(score)
        self.score = score
        -- Just update the score without sound for now
        print("Score changed to: " .. score)
    end)

    EventSystem.subscribe("gameOver", function()
        self.gameState = "gameOver"
        _G.gameStateForDrawing = "gameOver"
        print("Game state changed to gameOver")
    end)

    EventSystem.subscribe("startGame", function()
        self.gameState = "playing"
        _G.gameStateForDrawing = "playing"
        print("Game state changed to playing")
    end)
end

function UISystem:update()
    -- Store the state and score for use in the direct drawing
    _G.gameStateForDrawing = self.gameState
    _G.scoreForDrawing = self.score

    -- Handle restart button press
    if self.gameState == "gameOver" and playdate.buttonJustPressed(playdate.kButtonA) then
        EventSystem.emit("startGame")
    end
end

-- This will be called directly from playdate.update
function drawUI()
    -- Access the global variables
    local gameState = _G.gameStateForDrawing or "title"
    local score = _G.scoreForDrawing or 0

    -- Draw score during gameplay
    if gameState == "playing" then
        gfx.drawText("Score: " .. score, 5, 5)
    end

    -- Draw game state text using the default system font
    if gameState == "title" then
        -- Draw a nice title screen
        -- Title frame
        gfx.setLineWidth(3)
        gfx.drawRoundRect(SCREEN_WIDTH / 2 - 120, SCREEN_HEIGHT / 2 - 60, 240, 120, 8)
        gfx.setLineWidth(1)

        -- Game title
        gfx.drawText("FLAPPY DATE", SCREEN_WIDTH / 2 - 40, SCREEN_HEIGHT / 2 - 40)

        -- Instructions
        gfx.drawText("Press A to start", SCREEN_WIDTH / 2 - 50, SCREEN_HEIGHT / 2)
        gfx.drawText("Press A to flap wings", SCREEN_WIDTH / 2 - 65, SCREEN_HEIGHT / 2 + 20)
        gfx.drawText("Avoid pipes", SCREEN_WIDTH / 2 - 35, SCREEN_HEIGHT / 2 + 40)
    elseif gameState == "gameOver" then
        -- Draw game over screen
        -- Frame
        gfx.setLineWidth(3)
        gfx.drawRoundRect(SCREEN_WIDTH / 2 - 120, SCREEN_HEIGHT / 2 - 60, 240, 120, 8)
        gfx.setLineWidth(1)

        -- Game over text
        gfx.drawText("GAME OVER", SCREEN_WIDTH / 2 - 35, SCREEN_HEIGHT / 2 - 40)
        gfx.drawText("Final Score: " .. score, SCREEN_WIDTH / 2 - 45, SCREEN_HEIGHT / 2)
        gfx.drawText("Press A to restart", SCREEN_WIDTH / 2 - 55, SCREEN_HEIGHT / 2 + 40)
    end
end

-- ==========================================
-- Game Management
-- ==========================================
local gameWorld = World()
local pipeSpawnSystem = nil
local scoreTracker = nil

function initGame()
    print("Initializing game...")

    -- Setup systems
    gameWorld:addSystem(InputSystem())
    gameWorld:addSystem(MovementSystem())
    gameWorld:addSystem(CollisionSystem())
    pipeSpawnSystem = gameWorld:addSystem(PipeSpawnSystem())

    -- Setup UI system and initialize game state to title
    local uiSystem = UISystem()
    gameWorld:addSystem(uiSystem)

    -- Set initial state
    _G.gameStateForDrawing = "title"
    _G.scoreForDrawing = 0

    -- Create score tracker entity
    scoreTracker = Actor()
    scoreTracker:addComponent(ScoreComponent)
    gameWorld:addActor(scoreTracker)

    -- Setup event listeners
    EventSystem.subscribe("startGame", startGame)
    EventSystem.subscribe("gameOver", gameOver)
    EventSystem.subscribe("birdFlap", function()
        -- Just log flapping without sound for now
        print("Bird flap")
    end)

    print("Game initialization complete")
end

function startGame()
    print("Game starting...")
    print("Current game state: " .. (_G.gameStateForDrawing or "nil"))

    -- Explicitly set the game state
    _G.gameStateForDrawing = "playing"

    -- Force full cleanup of graphics state
    gfx.sprite.removeAll() -- Remove ALL sprites from the system
    gfx.sprite.redrawBackground()

    -- Completely reset drawing state
    _G.pipesForDrawing = nil
    _G.birdForDrawing = nil
    collectgarbage("collect") -- Force full garbage collection
    _G.pipesForDrawing = {}

    -- Stop any existing game activity
    gameWorld:stop()
    if pipeSpawnSystem then
        pipeSpawnSystem:stopSpawning()
    end

    -- Clear all actors from the world and recreate essential ones
    gameWorld.actors = {}
    print("Cleared all actors")

    -- Reset score
    _G.scoreForDrawing = 0

    -- Create a new score tracker
    scoreTracker = Actor()
    scoreTracker:addComponent(ScoreComponent)
    gameWorld:addActor(scoreTracker)
    print("Score reset to 0")

    -- Create bird with a more distinct bird-like shape
    local bird = Actor()
    local birdImage = gfx.image.new(32, 32)
    gfx.pushContext(birdImage)
    -- Body
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(16, 16, 12)

    -- Beak
    gfx.fillTriangle(24, 14, 32, 16, 24, 18)

    -- Eye
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(20, 13, 3)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(21, 13, 1)

    -- Wing
    gfx.drawLine(10, 18, 6, 24)
    gfx.drawLine(6, 24, 16, 22)
    gfx.popContext()

    -- Set the bird image and make sure it's visible and z-index is high
    bird:setImage(birdImage)
    bird:setZIndex(100)
    bird:setVisible(true)

    bird:addComponent(TransformComponent, 100, 120)
    bird:addComponent(PhysicsComponent, GRAVITY, 20, 20)
    bird:addComponent(BirdComponent)
    bird:addTag("bird")
    gameWorld:addActor(bird)

    -- Start pipe spawning
    pipeSpawnSystem:startSpawning()

    -- Draw something directly to make sure rendering is working
    gfx.fillCircleAtPoint(200, 120, 30)

    -- Start world
    gameWorld:start()

    -- Verify game is running correctly
    print("Game started. World active: " .. tostring(gameWorld.active))
    print("Game state: " .. (_G.gameStateForDrawing or "nil"))
end

function gameOver()
    gameWorld:stop()
    pipeSpawnSystem:stopSpawning()

    -- Ensure game state is updated
    _G.gameStateForDrawing = "gameOver"
    print("Game over called, stopping world and spawning")
end

-- ==========================================
-- Playdate Game Loop
-- ==========================================
function playdate.update()
    -- Start with fully clearing the screen
    gfx.clear(gfx.kColorWhite)

    -- Force complete sprite system refresh
    gfx.sprite.redrawBackground()

    -- Wrap game updates in pcall to catch errors
    local success, errorMsg = pcall(function()
        -- Update game world
        gameWorld:update()

        -- Update sprites
        gfx.sprite.update()

        -- Update timers
        playdate.timer.updateTimers()
    end)

    -- Clear everything again to ensure no stale graphics
    gfx.clear(gfx.kColorWhite)

    -- Draw a black border to ensure something is visible
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(0, 0, 400, 240)

    -- Check for button presses
    local buttonPressed = false
    if playdate.buttonJustPressed(playdate.kButtonA) then
        buttonPressed = true
        print("A button pressed!")

        -- Handle different states
        if _G.gameStateForDrawing == "title" then
            print("Starting game from title screen")
            EventSystem.emit("startGame")
        elseif _G.gameStateForDrawing == "gameOver" then
            print("Restarting game from game over screen")
            EventSystem.emit("startGame")
        end
    end

    -- Only draw game elements if we have valid data
    if _G.gameStateForDrawing == "playing" then
        -- Only draw pipes if we have actual pipe data
        if _G.pipesForDrawing and next(_G.pipesForDrawing) ~= nil then
            drawPipes() -- Draw pipes first (behind bird)
        else
            -- No pipes are active
            gfx.drawText("No pipes active", 280, 5)
        end

        -- Draw the bird
        drawBird()
    end

    -- Always draw the UI
    drawUI()

    -- If we hit an error, show it on screen
    if not success then
        gfx.drawTextAligned("ERROR: " .. tostring(errorMsg), SCREEN_WIDTH / 2, 40, gfx.kTextAlignCenter)
    end
end

-- Setup initial game assets and state
function playdate.gameWillStart()
    -- We'll need to use predefined assets instead of trying to create them at runtime
    -- The Playdate API doesn't support saving images or sounds at runtime in the way we attempted

    -- Since we cannot dynamically create assets, we'll modify our code to work with built-in shapes

    -- Debug sprites are now removed for clean gameplay

    -- Initialize game
    initGame()
end

-- Initialize game
playdate.gameWillStart()
