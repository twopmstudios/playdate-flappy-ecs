-- Celeste-style Platformer with Fixed Level Design
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

-- ==========================================
-- Components
-- ==========================================

class('PlayerComponent').extends(Component)

function PlayerComponent:init(actor)
    PlayerComponent.super.init(self, actor)

    -- Movement properties
    self.moveSpeed = 2
    self.jumpVelocity = -6
    self.isGrounded = false
    self.isJumping = false
    self.isFalling = false
    self.isDashing = false
    self.canDash = true
    self.isClimbing = false

    -- Dash properties
    self.dashSpeed = 12
    self.dashDuration = 100 -- milliseconds
    self.dashTimer = nil
    self.dashDirection = { x = 0, y = 0 }
    self.dashCooldown = 350 -- milliseconds
    self.dashCooldownTimer = nil

    -- Wall climbing properties
    self.isAgainstWall = false
    self.wallDirection = 0 -- -1 for left, 1 for right
    self.wallSlideSpeed = 1.2
    self.wallJumpVelocityX = 5
    self.canClimb = true
    self.climbSpeed = 2
    self.climbStamina = 100 -- Max stamina
    self.currentStamina = 100
    self.staminaDrainRate = 0.5
    self.staminaRecoveryRate = 0.3

    self.coyoteTime = 100 -- milliseconds
    self.coyoteTimer = nil
    self.wasGrounded = false

    -- Animation state
    self.facingDirection = 1 -- 1 = right, -1 = left
    self.animState = "idle"

    -- Create player image and animations
    self:createPlayerSprite()
end

function PlayerComponent:createPlayerSprite()
    -- Create more visible player sprite
    local playerImage = gfx.image.new(16, 16)
    gfx.pushContext(playerImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, 16, 16)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(2, 2, 12, 12)
    -- Add a distinguishing mark
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(4, 4, 8, 8)
    gfx.popContext()

    self.actor:setImage(playerImage)
    self.actor:setCollideRect(0, 0, 16, 16)
    self.actor:setZIndex(100) -- Player should be on top
end

function PlayerComponent:update()
    -- Update player state based on physics
    local physics = self.actor:getComponent(PhysicsComponent)

    -- Update animation state
    if self.isDashing then
        self.animState = "dash"
    elseif self.isClimbing then
        self.animState = "climb"
    elseif not self.isGrounded then
        if self.isAgainstWall then
            self.animState = "wallslide"
        elseif physics.velocity.y < 0 then
            self.animState = "jump"
        else
            self.animState = "fall"
        end
    else
        if math.abs(physics.velocity.x) > 0.1 then
            self.animState = "run"
        else
            self.animState = "idle"
        end
    end

    if self.isGrounded then
        self.wasGrounded = true
        if self.coyoteTimer then
            self.coyoteTimer:remove()
            self.coyoteTimer = nil
        end
    elseif self.wasGrounded and not self.isGrounded then
        self.wasGrounded = false
        self.coyoteTimer = playdate.timer.new(self.coyoteTime, function()
            self.coyoteTimer = nil
        end)
    end

    -- Stamina management when climbing
    if self.isClimbing then
        self.currentStamina = math.max(0, self.currentStamina - self.staminaDrainRate)
        if self.currentStamina <= 0 then
            self.canClimb = false
            self.isClimbing = false
        end
    elseif self.isGrounded then
        -- Recover stamina when on ground
        self.currentStamina = math.min(self.climbStamina, self.currentStamina + self.staminaRecoveryRate)
        self.canClimb = true
    end
end

function PlayerComponent:startDash(dirX, dirY)
    if self.canDash and not self.isDashing then
        self.isDashing = true
        self.canDash = false

        -- Normalize direction
        local length = math.sqrt(dirX * dirX + dirY * dirY)
        if length > 0 then
            dirX = dirX / length
            dirY = dirY / length
        else
            dirX = self.facingDirection
            dirY = 0
        end

        self.dashDirection = { x = dirX, y = dirY }

        -- Apply dash velocity
        local physics = self.actor:getComponent(PhysicsComponent)
        physics:setVelocity(
            self.dashDirection.x * self.dashSpeed,
            self.dashDirection.y * self.dashSpeed
        )

        -- Create dash timer
        if self.dashTimer then
            self.dashTimer:remove()
        end

        self.dashTimer = playdate.timer.new(self.dashDuration, function()
            self.isDashing = false

            -- Reset velocity after dash
            physics:setVelocity(
                physics.velocity.x * 0.3,
                physics.velocity.y * 0.3
            )

            -- Create cooldown timer
            if self.dashCooldownTimer then
                self.dashCooldownTimer:remove()
            end

            self.dashCooldownTimer = playdate.timer.new(self.dashCooldown, function()
                -- Allow dashing again after cooldown
                self.canDash = true
            end)
        end)

        -- Emit dash effect event
        EventSystem.emit("playerDash", self.actor.id, dirX, dirY)
    end
end

function PlayerComponent:startClimbing()
    if self.isAgainstWall and self.canClimb and not self.isDashing then
        self.isClimbing = true

        -- Stop vertical movement when starting to climb
        local physics = self.actor:getComponent(PhysicsComponent)
        physics:setVelocity(physics.velocity.x, 0)
    end
end

function PlayerComponent:stopClimbing()
    if self.isClimbing then
        self.isClimbing = false
    end
end

class('PlatformComponent').extends(Component)

function PlatformComponent:init(actor, width, height, movingProps)
    PlatformComponent.super.init(self, actor)
    self.width = width or 80
    self.height = height or 16
    self.type = "normal" -- normal, crumbling, moving, etc.

    -- For moving platforms
    self.isMoving = movingProps ~= nil
    if self.isMoving then
        self.moveSpeed = movingProps.speed or 1
        self.moveDistance = movingProps.distance or 100
        self.moveAxis = movingProps.axis or "x" -- "x" or "y"
        self.startPos = { x = 0, y = 0 }
        self.direction = 1                      -- 1 or -1
        self.distanceMoved = 0
    end

    -- Create platform image
    self:createPlatformSprite()
end

function PlatformComponent:createPlatformSprite()
    local platformImage = gfx.image.new(self.width, self.height)
    gfx.pushContext(platformImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, self.width, self.height)

    -- Different platform types have different appearances
    if self.type == "normal" then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(2, 2, self.width - 4, self.height - 4)
    end

    gfx.popContext()

    self.actor:setImage(platformImage)
    self.actor:setCollideRect(0, 0, self.width, self.height)
    self.actor:setZIndex(10)
end

function PlatformComponent:update()
    if self.isMoving then
        local transform = self.actor:getComponent(TransformComponent)

        -- If this is the first update, store the starting position
        if self.startPos.x == 0 and self.startPos.y == 0 then
            self.startPos.x = transform.x
            self.startPos.y = transform.y
        end

        local currentX = transform.x
        local currentY = transform.y
        local newX = currentX
        local newY = currentY

        -- Update platform position based on movement pattern
        if self.moveAxis == "x" then
            newX = currentX + (self.moveSpeed * self.direction)
            self.distanceMoved = math.abs(newX - self.startPos.x)

            if self.distanceMoved >= self.moveDistance then
                self.direction = self.direction * -1
                newX = currentX + (self.moveSpeed * self.direction)
            end
        else
            newY = currentY + (self.moveSpeed * self.direction)
            self.distanceMoved = math.abs(newY - self.startPos.y)

            if self.distanceMoved >= self.moveDistance then
                self.direction = self.direction * -1
                newY = currentY + (self.moveSpeed * self.direction)
            end
        end

        transform:setPosition(newX, newY)
    end
end

class('WallComponent').extends(Component)

function WallComponent:init(actor, width, height, isLeftWall)
    WallComponent.super.init(self, actor)
    self.width = width or 8
    self.height = height or 100
    self.isLeftWall = isLeftWall

    -- Create wall image
    self:createWallSprite()
end

function WallComponent:createWallSprite()
    local wallImage = gfx.image.new(self.width, self.height)
    gfx.pushContext(wallImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, self.width, self.height)
    gfx.popContext()

    self.actor:setImage(wallImage)
    self.actor:setCollideRect(0, 0, self.width, self.height)
    self.actor:setZIndex(10)
end

class('CameraComponent').extends(Component)

function CameraComponent:init(actor, targetActorId, offsetY)
    CameraComponent.super.init(self, actor)
    self.targetActorId = targetActorId
    self.offsetY = offsetY or -40 -- Reduced from -80 to show more of the screen
    self.smoothSpeed = 0.1        -- Lower for smoother camera

    -- Screen dimensions
    self.screenWidth = 400
    self.screenHeight = 240

    -- Initialize camera position to show content immediately
    self.currentScroll = 150
end

function CameraComponent:update()
    local world = self.actor:getComponent(WorldReferenceComponent).world
    if not world then return end

    local targetActor = world.actors[self.targetActorId]
    if not targetActor then return end

    local targetTransform = targetActor:getComponent(TransformComponent)
    if not targetTransform then return end

    -- Calculate desired y position (focus more on where the player is going)
    local desiredY = targetTransform.y + self.offsetY

    -- Smooth camera following
    self.currentScroll = self.currentScroll + (desiredY - self.currentScroll) * self.smoothSpeed

    -- Apply camera offset
    playdate.graphics.setDrawOffset(0, -self.currentScroll + self.screenHeight / 2)
end

class('WorldReferenceComponent').extends(Component)

function WorldReferenceComponent:init(actor, world)
    WorldReferenceComponent.super.init(self, actor)
    self.world = world
end

class('ParticleComponent').extends(Component)

function ParticleComponent:init(actor, lifetime, velocityX, velocityY)
    ParticleComponent.super.init(self, actor)
    self.lifetime = lifetime or 500 -- milliseconds
    self.timer = playdate.timer.new(self.lifetime, function()
        if self.actor then
            EventSystem.emit("removeActor", self.actor)
        end
    end)

    -- Add physics to the particle
    local physics = self.actor:getComponent(PhysicsComponent)
    if physics then
        physics:setVelocity(velocityX or 0, velocityY or 0)
    end
end

-- ==========================================
-- Systems
-- ==========================================

class('PlayerControlSystem').extends(System)

function PlayerControlSystem:update()
    local players = self.world:getActorsWithComponent(PlayerComponent)

    for _, playerActor in ipairs(players) do
        local player = playerActor:getComponent(PlayerComponent)
        local transform = playerActor:getComponent(TransformComponent)
        local physics = playerActor:getComponent(PhysicsComponent)

        if not player or not transform or not physics then
            goto continue
        end

        -- Skip input processing if dashing
        if player.isDashing then
            goto continue
        end

        -- Horizontal movement
        local moveInput = 0
        if playdate.buttonIsPressed(playdate.kButtonLeft) then
            moveInput = -1
            player.facingDirection = -1
        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
            moveInput = 1
            player.facingDirection = 1
        end

        -- Climbing movement
        if player.isClimbing then
            local climbInputY = 0
            if playdate.buttonIsPressed(playdate.kButtonUp) then
                climbInputY = -1
            elseif playdate.buttonIsPressed(playdate.kButtonDown) then
                climbInputY = 1
            end

            physics:setVelocity(
                moveInput * player.climbSpeed,
                climbInputY * player.climbSpeed
            )
        else
            -- Regular horizontal movement
            if player.isGrounded then
                physics:setVelocity(moveInput * player.moveSpeed, physics.velocity.y)
            else
                -- Air control is slightly less responsive
                if player.isAgainstWall and moveInput == player.wallDirection then
                    -- Don't push into the wall
                    physics:setVelocity(0, physics.velocity.y)
                else
                    physics:setVelocity(
                        physics.velocity.x + moveInput * (player.moveSpeed * 0.3),
                        physics.velocity.y
                    )
                    -- Cap horizontal air speed
                    physics.velocity.x = math.max(-player.moveSpeed, math.min(player.moveSpeed, physics.velocity.x))
                end
            end

            -- Wall slide
            if player.isAgainstWall and not player.isGrounded and physics.velocity.y > 0 then
                physics:setVelocity(physics.velocity.x, player.wallSlideSpeed)
            end
        end

        -- Jump
        if playdate.buttonIsPressed(playdate.kButtonA) then
            -- Only attempt to jump if grounded
            if player.isGrounded and not player.isJumping then
                -- Set a flag that we're jumping this frame
                player.isJumping = true

                -- Apply jump velocity
                local physics = player.actor:getComponent(PhysicsComponent)
                physics:setVelocity(physics.velocity.x, player.jumpVelocity)

                -- Emit jump effect event
                EventSystem.emit("playerJump", player.actor.id)

                print("Jump executed!")
            end
        elseif player.isJumping and not playdate.buttonIsPressed(playdate.kButtonA) then
            -- Button released, allow jumping again when grounded
            player.isJumping = false
        end

        -- Clear jumping state when landing
        if player.isGrounded and not playdate.buttonIsPressed(playdate.kButtonA) then
            player.isJumping = false
        end

        -- Climb/grab wall
        if playdate.buttonIsPressed(playdate.kButtonB) then
            player:startClimbing()
        else
            player:stopClimbing()
        end

        -- Dash (using crank for dash direction)
        if playdate.buttonJustPressed(playdate.kButtonDown) and playdate.buttonIsPressed(playdate.kButtonB) then
            -- Get dash direction from crank position
            local crankPos = playdate.getCrankPosition()
            local dashDirX = math.cos(math.rad(crankPos))
            local dashDirY = math.sin(math.rad(crankPos))

            -- If crank isn't being used, dash in movement or facing direction
            if dashDirX == 0 and dashDirY == 0 then
                dashDirX = moveInput ~= 0 and moveInput or player.facingDirection
                dashDirY = 0
            end

            player:startDash(dashDirX, dashDirY)
        end

        ::continue::
    end
end

class('PhysicsSystem').extends(System)

function PhysicsSystem:update()
    local physicsObjects = self.world:getActorsWithComponent(PhysicsComponent)

    for _, actor in ipairs(physicsObjects) do
        -- Skip physics for player actors - handled by CollisionSystem
        if actor:hasComponent(PlayerComponent) then
            goto continue
        end

        local physics = actor:getComponent(PhysicsComponent)
        local transform = actor:getComponent(TransformComponent)

        if physics and transform then
            -- Apply gravity
            physics.velocity.y = physics.velocity.y + physics.gravity

            -- Avoid very tiny movements that could cause vibration
            if math.abs(physics.velocity.y) < 0.01 then
                physics.velocity.y = 0
            end
            if math.abs(physics.velocity.x) < 0.01 then
                physics.velocity.x = 0
            end

            -- Update position
            transform:setPosition(transform.x + physics.velocity.x, transform.y + physics.velocity.y)
        end

        ::continue::
    end
end

class('CollisionSystem').extends(System)

function CollisionSystem:init(world)
    CollisionSystem.super.init(self, world)
    self.gravity = 0.35
end

function CollisionSystem:update()
    local players = self.world:getActorsWithComponent(PlayerComponent)
    local platforms = self.world:getActorsWithComponent(PlatformComponent)
    local walls = self.world:getActorsWithComponent(WallComponent)

    for _, playerActor in ipairs(players) do
        local player = playerActor:getComponent(PlayerComponent)
        local physics = playerActor:getComponent(PhysicsComponent)
        local transform = playerActor:getComponent(TransformComponent)

        if not player or not physics or not transform then
            goto continuePlayer
        end

        -- Reset collision flags
        player.isGrounded = false
        player.isAgainstWall = false
        player.wallDirection = 0

        -- Apply gravity only once (not in moveWithCollision)
        if not player.isDashing and not player.isClimbing then
            physics.velocity.y = physics.velocity.y + physics.gravity
        end

        -- Clamp velocity to prevent extreme speeds
        physics.velocity.x = math.max(-12, math.min(12, physics.velocity.x))
        physics.velocity.y = math.max(-15, math.min(15, physics.velocity.y))

        -- Perform movement with collision detection (without gravity inside)
        local collided, collidedObject, normalX, normalY, collisionType =
            physics:moveWithCollision(platforms, walls)

        -- Handle collision response with better physics
        if collided then
            if normalY == -1 then -- Hit something from below (ground)
                player.isGrounded = true

                -- Don't completely zero vertical velocity, reduce it significantly
                physics.velocity.y = physics.velocity.y * 0.1

                -- Reset jump state when grounded
                if not playdate.buttonIsPressed(playdate.kButtonA) then
                    player.isJumping = false
                end

                -- Reset dash ability when landing
                player.canDash = true
            elseif normalX ~= 0 then -- Hit a wall
                player.isAgainstWall = true
                player.wallDirection = normalX

                -- Allow slight sliding down wall
                if not player.isClimbing then
                    physics.velocity.x = physics.velocity.x * 0.2
                end
            end
        end

        ::continuePlayer::
    end
end

class('CameraSystem').extends(System)

function CameraSystem:update()
    local cameras = self.world:getActorsWithComponent(CameraComponent)

    for _, cameraActor in ipairs(cameras) do
        local camera = cameraActor:getComponent(CameraComponent)
        if camera then
            camera:update()
        end
    end
end

class('LevelSystem').extends(System)

function LevelSystem:init(world)
    LevelSystem.super.init(self, world)
    self.wallThickness = 8
    self.isLevelCreated = false

    -- Subscribe to actor removal
    EventSystem.subscribe("removeActor", function(actor)
        if actor then
            self.world:removeActor(actor)
        end
    end)
end

function LevelSystem:update()
    if not self.isLevelCreated then
        self:createFixedLevel()
        self.isLevelCreated = true
    end
end

function LevelSystem:createFixedLevel()
    -- Create ground
    self:createPlatform(200, 200, 200, 20)

    -- Create side walls
    self:createWall(self.wallThickness / 2, 120, self.wallThickness, 240, true)
    self:createWall(400 - self.wallThickness / 2, 120, self.wallThickness, 240, false)

    -- Create platforms - design a simple level with interesting jumps
    self:createPlatform(100, 150, 80, 16)
    self:createPlatform(300, 150, 80, 16)
    self:createPlatform(200, 110, 60, 16)
    self:createPlatform(100, 70, 60, 16)
    self:createPlatform(300, 70, 60, 16)
    self:createPlatform(200, 30, 100, 16)

    -- Add some moving platforms for challenge
    self:createPlatform(150, 100, 40, 12, { speed = 0.8, distance = 80, axis = "x" })
    self:createPlatform(250, 40, 40, 12, { speed = 0.8, distance = 80, axis = "x" })

    -- Create vertical platforms
    self:createPlatform(350, 100, 30, 12, { speed = 0.6, distance = 60, axis = "y" })

    print("Fixed level created")
end

function LevelSystem:createPlatform(x, y, width, height, movingProps)
    local platformActor = Actor()
    platformActor:addComponent(TransformComponent, x, y)
    platformActor:addComponent(PlatformComponent, width, height, movingProps)
    self.world:addActor(platformActor)
end

function LevelSystem:createWall(x, y, width, height, isLeftWall)
    local wallActor = Actor()
    wallActor:addComponent(TransformComponent, x, y)
    wallActor:addComponent(WallComponent, width, height, isLeftWall)
    self.world:addActor(wallActor)
end

class('ParticleSystem').extends(System)

function ParticleSystem:init(world)
    ParticleSystem.super.init(self, world)

    -- Subscribe to particle creation events
    EventSystem.subscribe("playerJump", function(actorId)
        self:createJumpParticles(actorId)
    end)

    EventSystem.subscribe("playerDash", function(actorId, dirX, dirY)
        self:createDashParticles(actorId, dirX, dirY)
    end)
end

function ParticleSystem:createJumpParticles(actorId)
    local actor = self.world.actors[actorId]
    if not actor then return end

    local transform = actor:getComponent(TransformComponent)
    if not transform then return end

    -- Create 5-8 particles
    local particleCount = math.random(5, 8)

    for _ = 1, particleCount do
        local particleActor = Actor()

        -- Create small white square
        local particleSize = math.random(2, 4)
        local particleImage = gfx.image.new(particleSize, particleSize)
        gfx.pushContext(particleImage)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(0, 0, particleSize, particleSize)
        gfx.popContext()

        particleActor:setImage(particleImage)
        particleActor:setZIndex(90) -- Below player but above platforms

        -- Random velocity from the player's position
        local vx = math.random(-2, 2)
        local vy = math.random(1, 3)

        particleActor:addComponent(TransformComponent, transform.x, transform.y + 8)
        -- particleActor:addComponent(PhysicsComponent, 0.1, particleSize, particleSize)
        particleActor:addComponent(ParticleComponent, 500, vx, vy)

        self.world:addActor(particleActor)
    end
end

function ParticleSystem:createDashParticles(actorId, dirX, dirY)
    local actor = self.world.actors[actorId]
    if not actor then return end

    local transform = actor:getComponent(TransformComponent)
    if not transform then return end

    -- Create a trail of particles
    local particleCount = 10

    for _ = 1, particleCount do
        local particleActor = Actor()

        -- Create small particle that fades away
        local particleSize = math.random(3, 6)
        local particleImage = gfx.image.new(particleSize, particleSize)
        gfx.pushContext(particleImage)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(0, 0, particleSize, particleSize)
        gfx.popContext()

        particleActor:setImage(particleImage)
        particleActor:setZIndex(90)

        -- Position slightly offset from player
        local offsetX = math.random(-5, 5)
        local offsetY = math.random(-5, 5)

        -- Velocity opposite of dash direction
        local vx = -dirX * math.random(0.5, 1.5)
        local vy = -dirY * math.random(0.5, 1.5)

        particleActor:addComponent(TransformComponent, transform.x + offsetX, transform.y + offsetY)
        -- particleActor:addComponent(PhysicsComponent, 0.05, particleSize, particleSize)
        particleActor:addComponent(ParticleComponent, 300, vx, vy)

        self.world:addActor(particleActor)
    end
end

function ParticleSystem:update()
    -- Particles update themselves via their timers
end

-- ==========================================
-- UI System for showing controls
-- ==========================================

class('UISystem').extends(System)

function UISystem:init(world)
    UISystem.super.init(self, world)
    self.showControls = true
    self.controlsFadeTimer = nil

    -- Create more visible UI actor
    local uiActor = Actor()
    local uiImage = gfx.image.new(400, 240)

    gfx.pushContext(uiImage)
    gfx.clear(gfx.kColorClear)
    -- Add a semi-transparent background
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(0.7)
    gfx.fillRect(50, 175, 300, 60)
    gfx.setDitherPattern(0)
    -- Draw text
    gfx.setColor(gfx.kColorWhite)
    gfx.drawTextAligned("CONTROLS:", 200, 180, kTextAlignment.center)
    gfx.drawTextAligned("D-Pad: Move   A: Jump   B: Climb", 200, 200, kTextAlignment.center)
    gfx.drawTextAligned("Down+B: Dash (use crank to aim)", 200, 220, kTextAlignment.center)
    gfx.popContext()

    uiActor:setImage(uiImage)
    uiActor:setZIndex(1000)
    uiActor:setIgnoresDrawOffset(true)

    self.uiActor = uiActor
    world:addActor(uiActor)

    -- Hide controls after a longer time to ensure visibility
    self.controlsFadeTimer = playdate.timer.new(8000, function()
        self.showControls = false
        self.uiActor:remove()
    end)
end

function UISystem:update()
    -- UI updates are handled by timers
end

-- ==========================================
-- Debug System
-- ==========================================

class('DebugSystem').extends(System)

function DebugSystem:update()
    -- Get player position for debug display
    local players = self.world:getActorsWithComponent(PlayerComponent)
    local platforms = self.world:getActorsWithComponent(PlatformComponent)

    if #players > 0 then
        local playerTransform = players[1]:getComponent(TransformComponent)
        if playerTransform then
            gfx.drawText("Player pos: " .. math.floor(playerTransform.x) .. ", " ..
                math.floor(playerTransform.y), 5, 5)
        end
    end

    gfx.drawText("Platforms: " .. #platforms, 5, 20)
end

-- ==========================================
-- Setup function to initialize the game
-- ==========================================

function setupCelesteGame(world)
    -- Create player at a lower position to match visible platforms
    local playerActor = Actor()
    playerActor:addComponent(TransformComponent, 200, 170)
    playerActor:addComponent(PhysicsComponent, 0.35, 16, 16)
    playerActor:addComponent(PlayerComponent)
    playerActor:addTag("player")
    world:addActor(playerActor)

    -- Add systems
    local collisionSystem = world:addSystem(CollisionSystem())
    local playerControlSystem = world:addSystem(PlayerControlSystem())
    local physicsSystem = world:addSystem(PhysicsSystem())
    local levelSystem = world:addSystem(LevelSystem())
    local cameraSystem = world:addSystem(CameraSystem())
    local particleSystem = world:addSystem(ParticleSystem())
    local uiSystem = world:addSystem(UISystem(world))
    local debugSystem = world:addSystem(DebugSystem())

    -- Setup dependencies - collisionSystem must run before playerControlSystem
    world:setupDependency(collisionSystem, playerControlSystem)
    -- physics should run after player control
    world:setupDependency(playerControlSystem, physicsSystem)

    -- Start the world
    world:start()

    print("Celeste-style Platformer initialized!")
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
    -- Initialize celeste platformer
    setupCelesteGame(gameWorld)
end

-- Initialize game
playdate.gameWillStart()
