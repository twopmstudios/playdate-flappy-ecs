-- FlappyDate: Actor-Based Flappy Bird Clone for Playdate
-- main.lua

import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/ui"
import "CoreLibs/object"
import "CoreLibs/crank"
import "CoreLibs/keyboard"

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
local PIPE_SPAWN_TIME = 2000  -- milliseconds
local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240

-- ==========================================
-- Event System
-- ==========================================
local EventSystem = {}
EventSystem.listeners = {}

function EventSystem.subscribe(eventName, callback)
    if not EventSystem.listeners[eventName] then
        EventSystem.listeners[eventName] = {}
    end
    table.insert(EventSystem.listeners[eventName], callback)
    return #EventSystem.listeners[eventName]  -- Return index for unsubscribe
end

function EventSystem.unsubscribe(eventName, index)
    if EventSystem.listeners[eventName] then
        EventSystem.listeners[eventName][index] = nil
    end
end

function EventSystem.emit(eventName, data)
    if EventSystem.listeners[eventName] then
        for _, callback in pairs(EventSystem.listeners[eventName]) do
            callback(data)
        end
    end
end

-- ==========================================
-- Component System
-- ==========================================
class('Component').extends()

function Component:init(actor)
    self.actor = actor
end

function Component:update() end
function Component:onAdd() end
function Component:onRemove() end

-- ==========================================
-- Actor System (Entity)
-- ==========================================
class('Actor').extends(gfx.sprite)

function Actor:init()
    -- Make sure we properly initialize the sprite base class
    gfx.sprite.init(self)
    
    -- Initialize our actor-specific properties
    self.components = {}
    self.tags = {}
    self.id = tostring(math.random(1000000))
    
    -- Ensure basic visibility settings
    self:setVisible(true)
    self:setZIndex(10)
    
    print("Actor initialized: " .. self.id)
end

function Actor:addComponent(componentClass, ...)
    local component = componentClass(self, ...)
    self.components[componentClass.className] = component
    component:onAdd()
    return component
end

function Actor:removeComponent(componentClass)
    local component = self.components[componentClass.className]
    if component then
        component:onRemove()
        self.components[componentClass.className] = nil
    end
end

function Actor:getComponent(componentClass)
    return self.components[componentClass.className]
end

function Actor:hasComponent(componentClass)
    return self.components[componentClass.className] ~= nil
end

function Actor:addTag(tag)
    self.tags[tag] = true
end

function Actor:removeTag(tag)
    self.tags[tag] = nil
end

function Actor:hasTag(tag)
    return self.tags[tag] == true
end

function Actor:update()
    for _, component in pairs(self.components) do
        component:update()
    end
end

-- ==========================================
-- World/Scene Manager
-- ==========================================
class('World').extends()

function World:init()
    self.actors = {}
    self.systems = {}
    self.active = false
end

function World:addActor(actor)
    self.actors[actor.id] = actor
    -- Add to Playdate sprite system
    -- We're removing the isAdded check since that method doesn't exist
    actor:add()
    print("Added actor " .. actor.id .. " to sprite system")
    return actor
end

function World:removeActor(actor)
    if self.actors[actor.id] then
        actor:remove()  -- Remove from Playdate sprite system
        self.actors[actor.id] = nil
    end
end

function World:addSystem(system)
    table.insert(self.systems, system)
    system:init(self)
    return system
end

function World:update()
    if not self.active then return end
    
    for _, system in ipairs(self.systems) do
        system:update()
    end
end

function World:start()
    self.active = true
end

function World:stop()
    self.active = false
end

function World:getActorsWithComponent(componentClass)
    local result = {}
    for _, actor in pairs(self.actors) do
        if actor:hasComponent(componentClass) then
            table.insert(result, actor)
        end
    end
    return result
end

function World:getActorsWithTag(tag)
    local result = {}
    for _, actor in pairs(self.actors) do
        if actor:hasTag(tag) then
            table.insert(result, actor)
        end
    end
    return result
end

-- ==========================================
-- System Base Class
-- ==========================================
class('System').extends()

function System:init(world)
    self.world = world
end

function System:update() end

-- ==========================================
-- Game-Specific Components
-- ==========================================
class('TransformComponent').extends(Component)

function TransformComponent:init(actor, x, y, rotation)
    TransformComponent.super.init(self, actor)
    self.x = x or 0
    self.y = y or 0
    self.rotation = rotation or 0
    self.actor:moveTo(self.x, self.y)
    self.actor:setRotation(self.rotation)
end

function TransformComponent:setPosition(x, y)
    self.x = x
    self.y = y
    self.actor:moveTo(self.x, self.y)
end

function TransformComponent:setRotation(rotation)
    self.rotation = rotation
    self.actor:setRotation(self.rotation)
end

class('PhysicsComponent').extends(Component)

function PhysicsComponent:init(actor, gravity, width, height)
    PhysicsComponent.super.init(self, actor)
    self.velocity = {x = 0, y = 0}
    self.gravity = gravity or 0
    self.width = width or 20
    self.height = height or 20
end

function PhysicsComponent:update()
    local transform = self.actor:getComponent(TransformComponent)
    if transform then
        -- Apply gravity
        self.velocity.y = self.velocity.y + self.gravity
        
        -- Update position
        transform:setPosition(transform.x + self.velocity.x, transform.y + self.velocity.y)
    end
end

function PhysicsComponent:applyForce(x, y)
    self.velocity.x = self.velocity.x + (x or 0)
    self.velocity.y = self.velocity.y + (y or 0)
end

function PhysicsComponent:setVelocity(x, y)
    self.velocity.x = x or self.velocity.x
    self.velocity.y = y or self.velocity.y
end

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
        
        -- Draw at the stored position
        gfx.fillCircleAtPoint(bird.x, bird.y, 12)
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
    local topPipeImage = gfx.image.new(self.width, self.gapY - self.gap/2)
    gfx.pushContext(topPipeImage)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(0, 0, self.width, self.gapY - self.gap/2)
    gfx.popContext()
    
    -- Create bottom pipe
    local bottomPipeImage = gfx.image.new(self.width, SCREEN_HEIGHT - (self.gapY + self.gap/2))
    gfx.pushContext(bottomPipeImage)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(0, 0, self.width, SCREEN_HEIGHT - (self.gapY + self.gap/2))
    gfx.popContext()
    
    -- Create and position the sprites
    self.topPipe = gfx.sprite.new(topPipeImage)
    self.topPipe:moveTo(self.actor:getComponent(TransformComponent).x, (self.gapY - self.gap/2) / 2)
    self.topPipe:setZIndex(20)
    self.topPipe:add()
    print("Top pipe sprite added")
    
    self.bottomPipe = gfx.sprite.new(bottomPipeImage)
    self.bottomPipe:moveTo(self.actor:getComponent(TransformComponent).x, self.gapY + self.gap/2 + (SCREEN_HEIGHT - (self.gapY + self.gap/2)) / 2)
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
        
        -- Draw all pipes
        for id, pipe in pairs(_G.pipesForDrawing) do
            -- Top pipe
            local topHeight = pipe.gapY - pipe.gap/2
            gfx.fillRect(pipe.x - pipe.width/2, 0, pipe.width, topHeight)
            
            -- Bottom pipe
            local bottomY = pipe.gapY + pipe.gap/2
            gfx.fillRect(pipe.x - pipe.width/2, bottomY, pipe.width, SCREEN_HEIGHT - bottomY)
        end
    end
end

function PipeComponent:onRemove()
    self.topPipe:remove()
    self.bottomPipe:remove()
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
        if transform.x < -PIPE_WIDTH/2 then
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
            if not pipeComponent.passed and birdTransform.x > pipeTransform.x + pipeComponent.width/2 then
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
    
    local birdLeft = birdTransform.x - birdPhysics.width/2
    local birdRight = birdTransform.x + birdPhysics.width/2
    local birdTop = birdTransform.y - birdPhysics.height/2
    local birdBottom = birdTransform.y + birdPhysics.height/2
    
    local pipeLeft = pipeTransform.x - pipeComponent.width/2
    local pipeRight = pipeTransform.x + pipeComponent.width/2
    
    local topPipeBottom = pipeComponent.gapY - pipeComponent.gap/2
    local bottomPipeTop = pipeComponent.gapY + pipeComponent.gap/2
    
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
    pipe:addComponent(TransformComponent, SCREEN_WIDTH + PIPE_WIDTH/2, SCREEN_HEIGHT/2)
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
        gfx.drawRoundRect(SCREEN_WIDTH/2 - 120, SCREEN_HEIGHT/2 - 60, 240, 120, 8)
        gfx.setLineWidth(1)
        
        -- Game title
        gfx.drawTextAligned("FLAPPY DATE", SCREEN_WIDTH/2, SCREEN_HEIGHT/2 - 40, gfx.kTextAlignCenter)
        
        -- Instructions
        gfx.drawTextAligned("Press A to start", SCREEN_WIDTH/2, SCREEN_HEIGHT/2, gfx.kTextAlignCenter)
        gfx.drawTextAligned("Press A to flap wings", SCREEN_WIDTH/2, SCREEN_HEIGHT/2 + 20, gfx.kTextAlignCenter)
        gfx.drawTextAligned("Avoid pipes", SCREEN_WIDTH/2, SCREEN_HEIGHT/2 + 40, gfx.kTextAlignCenter)
        
    elseif gameState == "gameOver" then
        -- Draw game over screen
        -- Frame
        gfx.setLineWidth(3)
        gfx.drawRoundRect(SCREEN_WIDTH/2 - 120, SCREEN_HEIGHT/2 - 60, 240, 120, 8)
        gfx.setLineWidth(1)
        
        -- Game over text
        gfx.drawTextAligned("GAME OVER", SCREEN_WIDTH/2, SCREEN_HEIGHT/2 - 40, gfx.kTextAlignCenter)
        gfx.drawTextAligned("Final Score: " .. score, SCREEN_WIDTH/2, SCREEN_HEIGHT/2, gfx.kTextAlignCenter)
        gfx.drawTextAligned("Press A to restart", SCREEN_WIDTH/2, SCREEN_HEIGHT/2 + 40, gfx.kTextAlignCenter)
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
    
    -- Reset pipes for drawing
    _G.pipesForDrawing = {}
    
    -- Clear existing actors with certain tags
    for _, actor in pairs(gameWorld.actors) do
        if actor:hasTag("bird") or actor:hasTag("pipe") then
            gameWorld:removeActor(actor)
        end
    end
    
    -- Reset score
    scoreTracker:getComponent(ScoreComponent).score = 0
    _G.scoreForDrawing = 0
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
end

function gameOver()
    gameWorld:stop()
    pipeSpawnSystem:stopSpawning()
end

-- ==========================================
-- Playdate Game Loop
-- ==========================================
function playdate.update()
    -- Clear the screen at the beginning of each frame
    gfx.clear(gfx.kColorWhite)
    
    -- Wrap game updates in pcall to catch errors
    local success, errorMsg = pcall(function()
        -- Update game world
        gameWorld:update()
        
        -- Update sprites
        gfx.sprite.update()
        
        -- Update timers
        playdate.timer.updateTimers()
    end)
    
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
    
    -- Draw game elements directly
    drawPipes()  -- Draw pipes first (behind bird)
    drawBird()   -- Draw bird next
    drawUI()     -- Draw UI on top
    
    -- If we hit an error, show it on screen
    if not success then
        gfx.drawTextAligned("ERROR: " .. tostring(errorMsg), SCREEN_WIDTH/2, 40, gfx.kTextAlignCenter)
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
