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

-- Engine Constants
local gfx <const> = playdate.graphics
local geom <const> = playdate.geometry
local snd <const> = playdate.sound
-- Spray Painting Game using the provided ECS architecture

-- Import necessary libraries (assuming these are already imported in main.lua)
local gfx <const> = playdate.graphics

-- ==========================================
-- Components
-- ==========================================

class('CanvasComponent').extends(Component)

function CanvasComponent:init(actor, width, height)
    CanvasComponent.super.init(self, actor)
    self.width = width or 400
    self.height = height or 240

    -- Create the canvas image we'll draw on
    self.canvasImage = gfx.image.new(self.width, self.height)
    gfx.pushContext(self.canvasImage)
    gfx.clear(gfx.kColorWhite)
    gfx.popContext()

    -- Paint density tracking for drips (using sparse grid)
    self.paintDensityMap = {}

    -- Set the canvas image on the actor
    self.actor:setImage(self.canvasImage)
    self.actor:moveTo(self.width / 2, self.height / 2)
    self.actor:setZIndex(1) -- Put canvas at the back
end

function CanvasComponent:update()
    -- The canvas will be updated by systems
end

function CanvasComponent:clearCanvas()
    gfx.pushContext(self.canvasImage)
    gfx.clear(gfx.kColorWhite)
    gfx.popContext()
    self.paintDensityMap = {}
    self.actor:markDirty() -- Tell Playdate the sprite needs to be redrawn
end

class('SprayCanComponent').extends(Component)

function SprayCanComponent:init(actor)
    SprayCanComponent.super.init(self, actor)
    self.pressure = 0      -- 0 to 1, controlled by crank
    self.sprayRadius = 5   -- Base radius, modified by pressure
    self.sprayColor = gfx.kColorBlack
    self.cursorImage = nil -- Will hold spray radius indicator

    -- Create and setup cursor sprite
    self:updateCursorImage()
    self.actor:setZIndex(100) -- Keep cursor on top
end

function SprayCanComponent:updateCursorImage()
    local size = math.floor(self.sprayRadius * (1 + self.pressure * 2)) * 2 + 4
    self.cursorImage = gfx.image.new(size, size)

    gfx.pushContext(self.cursorImage)
    gfx.clear(gfx.kColorClear)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.drawCircleAtPoint(size / 2, size / 2, size / 2 - 2)
    gfx.setLineWidth(1)
    gfx.popContext()

    self.actor:setImage(self.cursorImage)
end

function SprayCanComponent:update()
    -- Update cursor size based on pressure
    self:updateCursorImage()
end

-- ==========================================
-- Systems
-- ==========================================

class('SprayInputSystem').extends(System)

function SprayInputSystem:update()
    local sprayCans = self.world:getActorsWithComponent(SprayCanComponent)

    for _, sprayCanActor in ipairs(sprayCans) do
        local transform = sprayCanActor:getComponent(TransformComponent)
        local sprayCan = sprayCanActor:getComponent(SprayCanComponent)

        -- Handle d-pad movement
        local dx, dy = 0, 0
        local moveSpeed = 3

        if playdate.buttonIsPressed(playdate.kButtonUp) then dy = -moveSpeed end
        if playdate.buttonIsPressed(playdate.kButtonDown) then dy = moveSpeed end
        if playdate.buttonIsPressed(playdate.kButtonLeft) then dx = -moveSpeed end
        if playdate.buttonIsPressed(playdate.kButtonRight) then dx = moveSpeed end

        -- Apply movement
        transform:setPosition(
            math.max(0, math.min(400, transform.x + dx)),
            math.max(0, math.min(240, transform.y + dy))
        )

        -- Handle crank for pressure
        local crankChange = playdate.getCrankChange()
        sprayCan.pressure = math.min(1.0, math.max(0, sprayCan.pressure + crankChange / 360 * 0.1))

        -- Press B to clear canvas
        if playdate.buttonJustPressed(playdate.kButtonB) then
            EventSystem.emit("clearCanvas")
        end
    end
end

class('SpraySystem').extends(System)

function SpraySystem:init(world)
    SpraySystem.super.init(self, world)
    self.isSprayActive = false
    self.lastX = 0
    self.lastY = 0

    local main_channel = snd.channel.new()
    local spraycan_instrument = snd.instrument.new()

    -- Create a synthesized spray sound
    self.spraySound = snd.synth.new(snd.kWaveSawtooth)
    self.spraySound:setADSR(0.01, 0.1, 0.2, 0.5)
    -- Apply lowpass filter to soften harsh frequencies
    self.sprayFilter = snd.twopolefilter.new(snd.kFilterLowPass)
    self.sprayFilter:setFrequency(1200)
    self.sprayFilter:setResonance(0.1)

    -- Add noise for more realistic spray sound
    self.noiseSound = snd.synth.new(snd.kWaveNoise)
    self.noiseSound:setADSR(0.01, 0.1, 0.5, 0.3)
    self.noiseSound:setVolume(0.3)
    -- Apply bandpass filter to remove harsh highs and rumbling lows
    self.noiseFilter = snd.twopolefilter.new(snd.kFilterBandPass)
    self.noiseFilter:setFrequency(800)
    self.noiseFilter:setResonance(0.5)

    spraycan_instrument:addVoice(self.spraySound)
    spraycan_instrument:addVoice(self.noiseSound)
    main_channel:addSource(self.noiseSound)
    main_channel:addEffect(self.sprayFilter)

    -- Subscribe to clear canvas event
    EventSystem.subscribe("clearCanvas", function()
        local canvasActors = self.world:getActorsWithComponent(CanvasComponent)
        if #canvasActors > 0 then
            canvasActors[1]:getComponent(CanvasComponent):clearCanvas()
        end
    end)
end

function SpraySystem:update()
    local canvasActors = self.world:getActorsWithComponent(CanvasComponent)
    if #canvasActors == 0 then return end

    local canvas = canvasActors[1]:getComponent(CanvasComponent)
    local sprayCans = self.world:getActorsWithComponent(SprayCanComponent)

    for _, sprayCanActor in ipairs(sprayCans) do
        local transform = sprayCanActor:getComponent(TransformComponent)
        local sprayCan = sprayCanActor:getComponent(SprayCanComponent)

        -- Check if A button is pressed (to spray)
        if playdate.buttonIsPressed(playdate.kButtonA) and sprayCan.pressure > 0 then
            -- Apply spray paint
            self:applySpray(canvas, transform.x, transform.y, sprayCan)

            -- Play spray sound effects with modifications based on pressure
            if not self.isSprayActive then
                -- Start the sounds
                self.spraySound:playNote(500 - sprayCan.pressure * 400)
                self.noiseSound:playNote(240 - sprayCan.pressure * 20)
                self.isSprayActive = true
            end

            -- Modulate sound based on pressure
            self.spraySound:setVolume(0.1 + sprayCan.pressure * 0.3)
            self.noiseSound:setVolume(0.3 + sprayCan.pressure * 0.4)
        else
            -- Stop spray sounds when not spraying
            if self.isSprayActive then
                self.spraySound:stop()
                self.noiseSound:stop()
                self.isSprayActive = false
            end
        end

        -- Store last position for interpolation
        self.lastX = transform.x
        self.lastY = transform.y
    end
end

function SpraySystem:applySpray(canvas, x, y, sprayCan)
    -- Apply paint to canvas image
    local radius = sprayCan.sprayRadius * (1 + sprayCan.pressure * 2)
    local density = sprayCan.pressure * 0.7

    gfx.pushContext(canvas.canvasImage)
    gfx.setColor(sprayCan.sprayColor)

    -- Create spray pattern (scattered dots)
    for i = 1, math.floor(30 * sprayCan.pressure) do
        local angle = math.random() * math.pi * 2
        local distance = math.random() * radius
        local px = x + math.cos(angle) * distance
        local py = y + math.sin(angle) * distance

        -- Don't draw outside canvas
        if px >= 0 and px < canvas.width and py >= 0 and py < canvas.height then
            gfx.fillCircleAtPoint(px, py, math.random(1, 2))

            -- Update density map for drips (using 4x4 grid cells)
            local gridX, gridY = math.floor(px / 4), math.floor(py / 4)
            local key = gridX .. "," .. gridY
            canvas.paintDensityMap[key] = (canvas.paintDensityMap[key] or 0) + density
        end
    end

    gfx.popContext()
    canvas.actor:markDirty() -- Update the sprite
end

class('DripSystem').extends(System)

function DripSystem:update()
    local canvasActors = self.world:getActorsWithComponent(CanvasComponent)
    if #canvasActors == 0 then return end

    local canvas = canvasActors[1]:getComponent(CanvasComponent)
    local needsUpdate = false

    gfx.pushContext(canvas.canvasImage)
    gfx.setColor(gfx.kColorBlack)

    -- Process each grid cell for potential drips
    for key, density in pairs(canvas.paintDensityMap) do
        -- Threshold for dripping
        if density > 0.8 then
            needsUpdate = true

            -- Parse grid coordinates
            local x, y = string.match(key, "(%d+),(%d+)")
            x, y = tonumber(x) * 4, tonumber(y) * 4

            -- Create a drip with randomized length based on density
            local dripLength = math.random(3, 10) * density
            gfx.fillRect(x, y, 2, dripLength)

            -- Transfer paint density down the canvas
            local newY = math.min(canvas.height / 4 - 1, math.floor((y + dripLength) / 4))
            local newKey = math.floor(x / 4) .. "," .. newY
            canvas.paintDensityMap[newKey] = (canvas.paintDensityMap[newKey] or 0) + 0.3

            -- Reduce original density
            canvas.paintDensityMap[key] = density * 0.7
        else
            -- Paint dries over time
            canvas.paintDensityMap[key] = density * 0.99
            if density < 0.01 then
                canvas.paintDensityMap[key] = nil -- Remove negligible amounts
            end
        end
    end

    gfx.popContext()

    if needsUpdate then
        canvas.actor:markDirty() -- Only update if changes occurred
    end
end

-- ==========================================
-- UI Component and System
-- ==========================================

class('UIComponent').extends(Component)

function UIComponent:init(actor)
    UIComponent.super.init(self, actor)
    self.uiImage = gfx.image.new(400, 240)
    self.actor:setImage(self.uiImage)
    self.actor:setZIndex(90)              -- Below cursor but above canvas
    self.actor:setIgnoresDrawOffset(true) -- UI stays fixed on screen
end

class('UISystem').extends(System)

function UISystem:update()
    local uiActors = self.world:getActorsWithComponent(UIComponent)
    if #uiActors == 0 then return end

    local ui = uiActors[1]:getComponent(UIComponent)
    local sprayCans = self.world:getActorsWithComponent(SprayCanComponent)

    if #sprayCans == 0 then return end

    local sprayCan = sprayCans[1]:getComponent(SprayCanComponent)

    -- Update UI
    gfx.pushContext(ui.uiImage)
    gfx.clear(gfx.kColorClear)

    -- Draw pressure indicator
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(10, 10, 104, 14)
    gfx.fillRect(12, 12, sprayCan.pressure * 100, 10)
    gfx.drawTextAligned("Pressure", 60, 25, kTextAlignment.center)

    -- Draw instructions
    gfx.drawTextAligned("D-Pad: Move   A: Spray   B: Clear", 200, 220, kTextAlignment.center)

    gfx.popContext()
    ui.actor:markDirty()
end

class('AccelerometerSpraySystem').extends(System)

function AccelerometerSpraySystem:init(world)
    AccelerometerSpraySystem.super.init(self, world)
    -- Initialize with default values
    self.lastX = 0
    self.lastY = 0
    -- Start the accelerometer - it's always available on Playdate
    playdate.startAccelerometer()
end

function AccelerometerSpraySystem:update()
    local sprayCans = self.world:getActorsWithComponent(SprayCanComponent)
    if #sprayCans == 0 then return end

    local sprayCanActor = sprayCans[1]
    local transform = sprayCanActor:getComponent(TransformComponent)

    -- Get accelerometer data
    local x, y, z = playdate.readAccelerometer()

    -- Apply some smoothing to prevent jitter
    local smoothFactor = 0.2
    self.lastX = self.lastX * (1 - smoothFactor) + x * smoothFactor
    self.lastY = self.lastY * (1 - smoothFactor) + y * smoothFactor

    -- Convert accelerometer tilt to movement
    -- Scale factor determines sensitivity
    local scaleFactor = 2.5
    local dx = self.lastX * scaleFactor
    local dy = self.lastY * scaleFactor

    -- Apply movement with boundaries
    transform:setPosition(
        math.max(10, math.min(390, transform.x + dx)),
        math.max(10, math.min(230, transform.y + dy))
    )
end

-- ==========================================
-- Setup function to initialize the game
-- ==========================================

function setupSprayPaintingGame(world)
    -- Create canvas
    local canvasActor = Actor()
    canvasActor:addComponent(TransformComponent, 200, 120)
    canvasActor:addComponent(CanvasComponent, 400, 240)
    world:addActor(canvasActor)

    -- Create spray can cursor
    local sprayCanActor = Actor()
    sprayCanActor:addComponent(TransformComponent, 200, 120)
    sprayCanActor:addComponent(SprayCanComponent)
    world:addActor(sprayCanActor)

    -- Create UI
    local uiActor = Actor()
    uiActor:addComponent(UIComponent)
    world:addActor(uiActor)

    -- Add systems
    world:addSystem(SprayInputSystem())
    world:addSystem(AccelerometerSpraySystem())
    world:addSystem(SpraySystem())
    world:addSystem(DripSystem())
    world:addSystem(UISystem())

    -- Start the world
    world:start()

    print("Spray Painting Game initialized!")
end

-- ==========================================
-- Game Management
-- ==========================================
local gameWorld = World()

function playdate.update()
    -- Update game world
    gameWorld:update()

    -- Update sprites
    gfx.sprite.update()

    -- Update timers
    playdate.timer.updateTimers()
end

-- Setup initial game assets and state
function playdate.gameWillStart()
    -- Initialize spray painting game
    setupSprayPaintingGame(gameWorld)
end

-- Initialize game
playdate.gameWillStart()
