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

class('BillboardComponent').extends(Component)

function BillboardComponent:init(actor, width, height)
    BillboardComponent.super.init(self, actor)
    self.width = width or 40
    self.height = height or 30
    self.hasGraffiti = false
    self.graffitiImage = nil
    
    -- Create billboard image
    self:createBillboardSprite()
end

function BillboardComponent:createBillboardSprite()
    local billboardImage = gfx.image.new(self.width, self.height)
    gfx.pushContext(billboardImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, self.width, self.height)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(2, 2, self.width-4, self.height-4)
    
    if self.hasGraffiti and self.graffitiImage then
        -- Draw the graffiti in the center if we have it
        self.graffitiImage:draw(self.width/2 - self.graffitiImage:getSize()/2, 
                               self.height/2 - self.graffitiImage:getSize()/2)
    else
        -- Draw an icon to indicate this is a graffiti spot
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(self.width/2-5, self.height/2-5, 10, 10)
        gfx.setLineWidth(1)
        gfx.drawLine(self.width/2-3, self.height/2-3, self.width/2+3, self.height/2+3)
        gfx.drawLine(self.width/2-3, self.height/2+3, self.width/2+3, self.height/2-3)
    end
    
    gfx.popContext()
    
    self.actor:setImage(billboardImage)
    self.actor:setCollideRect(0, 0, self.width, self.height)
    self.actor:setZIndex(5) -- Between platforms and player
end

function BillboardComponent:setGraffitiImage(image)
    self.graffitiImage = image
    self.hasGraffiti = true
    self:createBillboardSprite() -- Refresh the sprite
end

class('GameStateComponent').extends(Component)

function GameStateComponent:init(actor)
    GameStateComponent.super.init(self, actor)
    self.currentState = "platformer" -- "platformer" or "graffiti"
    self.activeBillboard = nil -- Will store the billboard actor when in graffiti mode
    self.graffitiCanvas = nil -- Will store the graffiti canvas when created
    self.playerPosition = {x = 0, y = 0} -- Store player position when entering graffiti mode
end

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
    self.dashSpeed = 14       -- Faster dash speed
    self.dashDuration = 150   -- Longer duration
    self.dashTimer = nil
    self.dashDirection = { x = 0, y = 0 }
    self.dashCooldown = 250   -- Shorter cooldown for more frequent dashes
    self.dashCooldownTimer = nil
    self.dashRefreshedByGround = true     -- Track if dash can be refreshed by touching ground
    self.hasDashed = false                -- Track if player has dashed mid-air
    self.dashEndLagDuration = 40          -- Short end lag after dashing before full control resumes
    self.dashEndLagTimer = nil

    -- Wall climbing properties
    self.isAgainstWall = false
    self.wallDirection = 0 -- -1 for left, 1 for right
    self.wallSlideSpeed = 1.2
    self.wallFrictionMultiplier = 0.7 -- Friction when pushing into wall
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
    self.lastAnimTime = 0
    self.currentFrame = 1

    -- Create player image and animations
    self:createPlayerSprite()
end

function PlayerComponent:createPlayerSprite()
    -- Animation frames for each state
    self.frames = {
        idle = {},
        run = {},
        jump = {},
        fall = {},
        dash = {},
        wallslide = {},
        climb = {}
    }
    
    self.currentFrame = 1
    self.animationDelay = 100 -- milliseconds between frames
    
    -- Attempt to load individual animation frames
    local loadedAnyFrames = false
    
    -- Try to load individual frame PNGs for running animation
    -- Format: frame-1.png, frame-2.png, frame-3.png, frame-4.png
    for i = 1, 4 do
        local framePath = "images/frame-" .. i .. ".png"
        local frameImage = gfx.image.new(framePath)
        
        if frameImage then
            print("Loaded animation frame: " .. framePath)
            
            -- Add to running animation
            self.frames.run[i] = frameImage
            
            -- For frames we want to use for other states
            if i == 1 then
                self.frames.idle[1] = frameImage
            elseif i == 2 then
                self.frames.jump[1] = frameImage
                self.frames.climb[1] = frameImage
            elseif i == 3 then
                self.frames.dash[1] = frameImage
                self.frames.wallslide[1] = frameImage
            elseif i == 4 then
                self.frames.fall[1] = frameImage
            end
            
            loadedAnyFrames = true
        else
            print("Failed to load animation frame: " .. framePath)
        end
    end
    
    -- Alternatively, try to load from a sprite table if export format changes
    if not loadedAnyFrames then
        print("Trying to load from wizzo.png...")
        -- Load from wizzo.png (just the first 16x16 region)
        local wizzo = gfx.image.new("wizzo.png")
        
        if wizzo then
            print("Successfully loaded wizzo.png")
            
            -- Extract all 4 frames (16x16 each) from the wizzo sprite sheet
            for i = 1, 4 do
                local frame = gfx.image.new(16, 16)
                gfx.pushContext(frame)
                gfx.setColor(gfx.kColorWhite)
                gfx.fillRect(0, 0, 16, 16)  -- Fill with white background
                gfx.setColor(gfx.kColorBlack)
                -- Each frame is 16x16 in a 64x16 image
                -- Simple approach: draw the full image but position it to show only the portion we want
                local frameX = (i-1) * 16  -- Each frame is 16px wide
                wizzo:draw(-frameX, 0)  -- Position the image so only the right segment is visible in our 16x16 frame
                gfx.popContext()
                
                -- Add to running animation
                self.frames.run[i] = frame
                
                -- For frames we want to use for other states
                if i == 1 then
                    self.frames.idle[1] = frame
                elseif i == 2 then
                    self.frames.jump[1] = frame
                    self.frames.climb[1] = frame
                elseif i == 3 then
                    self.frames.dash[1] = frame
                    self.frames.wallslide[1] = frame
                elseif i == 4 then
                    self.frames.fall[1] = frame
                end
            end
            
            loadedAnyFrames = true
        else
            print("Failed to load wizzo.png")
            
            -- Try loading from sprite table as another fallback
            print("Trying to load from sprite table...")
            local spritePath = "images/wizzo-table-1"
            local imageTable = gfx.imagetable.new(spritePath)
            
            if imageTable then
                print("Successfully loaded sprite table: " .. spritePath)
                
                -- Load frames from the image table
                for i = 1, 4 do
                    local frame = imageTable:getImage(i)
                    if frame then
                        self.frames.run[i] = frame
                        
                        -- For frames we want to use for other states
                        if i == 1 then
                            self.frames.idle[1] = frame
                        elseif i == 2 then
                            self.frames.jump[1] = frame
                            self.frames.climb[1] = frame
                        elseif i == 3 then
                            self.frames.dash[1] = frame
                            self.frames.wallslide[1] = frame
                        elseif i == 4 then
                            self.frames.fall[1] = frame
                        end
                        
                        loadedAnyFrames = true
                    end
                end
            else
                print("Failed to load sprite table")
            end
        end
    end
    
    if loadedAnyFrames then
        print("Successfully loaded animation frames from files")
    else
        print("Failed to load sprite sheet - using fallback sprites")
        
        -- Create fallback frames for each animation type
        for animType, _ in pairs(self.frames) do
            -- Create a different colored shape for each animation type
            local frameCount = animType == "run" and 4 or 1
            
            for i = 1, frameCount do
                local frameImage = gfx.image.new(16, 16)
                gfx.pushContext(frameImage)
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(0, 0, 16, 16)
                gfx.setColor(gfx.kColorWhite)
                
                -- Different shapes for different animation types
                if animType == "idle" then
                    gfx.fillCircleAtPoint(8, 8, 6)
                elseif animType == "run" then
                    gfx.fillRect(2, 2, 12, 12)
                    -- Add some variation for running frames
                    if i == 2 then
                        gfx.setColor(gfx.kColorBlack)
                        gfx.fillRect(4, 4, 2, 2)
                    elseif i == 3 then
                        gfx.setColor(gfx.kColorBlack)
                        gfx.fillRect(10, 4, 2, 2)
                    elseif i == 4 then
                        gfx.setColor(gfx.kColorBlack)
                        gfx.fillRect(7, 10, 2, 2)
                    end
                elseif animType == "jump" then
                    gfx.fillTriangle(8, 2, 14, 14, 2, 14)
                elseif animType == "fall" then
                    gfx.drawLine(4, 4, 12, 12)
                    gfx.drawLine(4, 12, 12, 4)
                elseif animType == "dash" then
                    gfx.fillRect(2, 6, 12, 4)
                elseif animType == "wallslide" then
                    gfx.fillRect(2, 2, 4, 12)
                elseif animType == "climb" then
                    gfx.fillRect(4, 2, 8, 12)
                end
                
                gfx.popContext()
                self.frames[animType][i] = frameImage
            end
        end
    end
    
    -- Make sure all animation states have at least one frame
    for animType, frames in pairs(self.frames) do
        if #frames == 0 then
            -- Create a fallback frame for any missing animations
            local fallbackImage = gfx.image.new(16, 16)
            gfx.pushContext(fallbackImage)
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(0, 0, 16, 16)
            gfx.setColor(gfx.kColorWhite)
            gfx.fillCircleAtPoint(8, 8, 6)
            gfx.popContext()
            
            self.frames[animType][1] = fallbackImage
            print("Created fallback frame for " .. animType .. " animation")
        end
    end
    
    -- Initialize with idle animation
    self.animState = "idle"
    self.lastAnimState = "idle"
    self.lastAnimTime = 0
    
    -- Set the first frame
    self.actor:setImage(self.frames[self.animState][1])
    self.actor:setCollideRect(0, 0, 16, 16)
    self.actor:setZIndex(100) -- Player should be on top
    
    print("Player sprite initialized with animations")
end

function PlayerComponent:update()
    -- Update player state based on physics
    local physics = self.actor:getComponent(PhysicsComponent)

    -- Update animation state
    local previousState = self.animState
    
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
    
    -- Only reset frame counter if we changed animation state
    if previousState ~= self.animState then
        self.currentFrame = 1
        print("Animation changed from " .. previousState .. " to " .. self.animState)
        
        -- Update image immediately on state change
        if self.frames[self.animState] and self.frames[self.animState][1] then
            self.actor:setImage(self.frames[self.animState][1])
        end
    end
    
    -- Update animation frames based on time
    local currentTime = playdate.getCurrentTimeMilliseconds()
    if self.lastAnimTime == 0 then 
        self.lastAnimTime = currentTime
    end
    
    local elapsed = currentTime - self.lastAnimTime
    if elapsed >= self.animationDelay then
        self:updateAnimationFrame()
        self.lastAnimTime = currentTime
    end
    
    -- Set sprite flip based on facing direction
    if self.facingDirection == -1 then
        self.actor:setImageFlip(gfx.kImageFlippedX)
    else
        self.actor:setImageFlip(gfx.kImageUnflipped)
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

function PlayerComponent:updateAnimationFrame()
    -- Only animations with multiple frames need to be advanced
    local framesInAnim = self.frames[self.animState]
    local frameCount = #framesInAnim
    
    -- If this animation has multiple frames, advance to the next one
    if frameCount > 1 then
        self.currentFrame = self.currentFrame + 1
        if self.currentFrame > frameCount then
            self.currentFrame = 1
        end
        
        if framesInAnim[self.currentFrame] then
            self.actor:setImage(framesInAnim[self.currentFrame])
        end
    end
end

function PlayerComponent:startDash(dirX, dirY)
    -- Check if can dash
    if (self.canDash or (self.isAgainstWall and not self.hasDashed)) and not self.isDashing then
        self.isDashing = true
        self.canDash = false
        
        if not self.isGrounded and not self.isAgainstWall then
            -- If in mid-air and not against a wall, mark that we've used our air dash
            self.hasDashed = true
        end
        
        -- Cancel any end lag
        if self.dashEndLagTimer then
            self.dashEndLagTimer:remove()
            self.dashEndLagTimer = nil
        end

        -- Ensure we have valid direction values
        if dirX == nil or dirY == nil then
            -- Default to facing direction
            dirX = self.facingDirection
            dirY = 0
            print("Corrected nil direction to: " .. dirX .. ", " .. dirY)
        end

        -- Normalize direction
        local length = math.sqrt(dirX * dirX + dirY * dirY)
        if length > 0 then
            dirX = dirX / length
            dirY = dirY / length
        else
            -- If for some reason we get a zero vector, force to facing direction
            dirX = self.facingDirection
            dirY = 0
            print("Corrected zero vector to: " .. dirX .. ", " .. dirY)
        end

        self.dashDirection = { x = dirX, y = dirY }

        -- Apply dash velocity
        local physics = self.actor:getComponent(PhysicsComponent)
        
        -- Completely override velocity for a more responsive dash
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
            
            -- Apply dash end effects - preserve some momentum in the dash direction
            local preserveMomentum = 0.5  -- Preserve half of dash velocity
            
            -- If dashing horizontally or diagonally upward, provide a small upward boost at the end
            local upwardBoost = 0
            if self.dashDirection.y <= 0 and math.abs(self.dashDirection.x) > 0 then
                upwardBoost = -2  -- Small upward boost to help with platforming
            end
            
            physics:setVelocity(
                self.dashDirection.x * self.dashSpeed * preserveMomentum,
                (self.dashDirection.y * self.dashSpeed * preserveMomentum) + upwardBoost
            )
            
            -- Update collision rect immediately to prevent visual inconsistency
            physics:updateCollisionRect()
            
            -- Create a brief period of dash end lag where control is limited
            self.dashEndLagTimer = playdate.timer.new(self.dashEndLagDuration, function()
                self.dashEndLagTimer = nil
            end)

            -- Create cooldown timer
            if self.dashCooldownTimer then
                self.dashCooldownTimer:remove()
            end

            self.dashCooldownTimer = playdate.timer.new(self.dashCooldown, function()
                -- Allow dashing again after cooldown, but only if we have our dash refreshed
                if self.dashRefreshedByGround then
                    self.canDash = true
                end
            end)
        end)

        -- Ensure we have valid direction values before emitting effects
        local dashDirX = self.dashDirection.x or 0
        local dashDirY = self.dashDirection.y or 0
        
        -- Emit dash effect event with higher intensity
        -- Generate more particles for a more satisfying effect
        for i = 1, 3 do -- Call event multiple times for more particles
            EventSystem.emit("playerDash", self.actor.id, dashDirX, dashDirY)
        end
        
        -- Add screen shake for juice
        -- This would normally be part of a camera system, but for simplicity
        -- we can just add a visual cue that the dash is powerful
        local shakeAmount = 2  -- Use integers for shake amount to avoid math.random errors
        local shakeDuration = 100
        EventSystem.emit("screenShake", shakeAmount, shakeDuration)
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
    
    -- Screen shake properties
    self.shakeAmount = 0
    self.shakeTimer = nil
    self.shakeOffsetX = 0
    self.shakeOffsetY = 0
    
    -- Subscribe to screen shake events
    EventSystem.subscribe("screenShake", function(amount, duration)
        self:startShake(amount, duration)
    end)
end

function CameraComponent:startShake(amount, duration)
    self.shakeAmount = amount
    
    -- Clear existing shake timer if there is one
    if self.shakeTimer then
        self.shakeTimer:remove()
    end
    
    -- Set up timer to stop shake after duration
    self.shakeTimer = playdate.timer.new(duration, function()
        self.shakeAmount = 0
        self.shakeOffsetX = 0
        self.shakeOffsetY = 0
        self.shakeTimer = nil
    end)
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
    
    -- Update screen shake if active
    if self.shakeAmount > 0 then
        -- Make sure shake amount is an integer to avoid errors
        local intShakeAmount = math.floor(self.shakeAmount)
        if intShakeAmount < 1 then intShakeAmount = 1 end
        
        -- Generate random offsets for shake
        self.shakeOffsetX = math.random(-intShakeAmount, intShakeAmount)
        self.shakeOffsetY = math.random(-intShakeAmount, intShakeAmount)
    else
        self.shakeOffsetX = 0
        self.shakeOffsetY = 0
    end

    -- Apply camera offset with shake
    playdate.graphics.setDrawOffset(
        self.shakeOffsetX, 
        -self.currentScroll + self.screenHeight / 2 + self.shakeOffsetY
    )
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

class('GameStateSystem').extends(System)

function GameStateSystem:init(world)
    GameStateSystem.super.init(self, world)
    
    -- Subscribe to graffiti mode events
    EventSystem.subscribe("enterGraffitiMode", function(billboardActor, playerX, playerY)
        self:enterGraffitiMode(billboardActor, playerX, playerY)
    end)
    
    EventSystem.subscribe("exitGraffitiMode", function()
        self:exitGraffitiMode()
    end)
    
    EventSystem.subscribe("saveGraffiti", function(canvasImage)
        self:saveGraffiti(canvasImage)
    end)
 end

function GameStateSystem:update()
    local stateActors = self.world:getActorsWithComponent(GameStateComponent)
    if #stateActors == 0 then return end
    
    local gameState = stateActors[1]:getComponent(GameStateComponent)
    
    -- Check for billboard interactions in platformer mode
    if gameState.currentState == "platformer" then
        -- Find player and billboards
        local players = self.world:getActorsWithComponent(PlayerComponent)
        local billboards = self.world:getActorsWithComponent(BillboardComponent)
        
        if #players == 0 then return end
        
        local player = players[1]
        local transform = player:getComponent(TransformComponent)
        
        -- Check if player is near a billboard and pressing B
        if playdate.buttonJustPressed(playdate.kButtonB) then
            for _, billboard in ipairs(billboards) do
                local billboardTransform = billboard:getComponent(TransformComponent)
                local billboardComponent = billboard:getComponent(BillboardComponent)
                
                -- Check proximity to billboard
                local dx = math.abs(transform.x - billboardTransform.x)
                local dy = math.abs(transform.y - billboardTransform.y)
                
                if dx < billboardComponent.width/2 + 16 and dy < billboardComponent.height/2 + 16 then
                    -- Enter graffiti mode
                    EventSystem.emit("enterGraffitiMode", billboard, transform.x, transform.y)
                    break
                end
            end
        end
    elseif gameState.currentState == "graffiti" then
        -- In graffiti mode, check for exit button
        if playdate.buttonJustPressed(playdate.kButtonB) then
            -- Save current canvas and exit graffiti mode
            local canvasActors = self.world:getActorsWithComponent(CanvasComponent)
            if #canvasActors > 0 then
                local canvas = canvasActors[1]:getComponent(CanvasComponent)
                if canvas and canvas.canvasImage then
                    -- Save the graffiti to the billboard first
                    EventSystem.emit("saveGraffiti", canvas.canvasImage)
                    -- Then exit graffiti mode after a short delay to ensure the saving completes
                    playdate.timer.performAfterDelay(50, function()
                        EventSystem.emit("exitGraffitiMode")
                    end)
                else
                    -- If no canvas, just exit
                    EventSystem.emit("exitGraffitiMode")
                end
            else
                -- If no canvas actors, just exit
                EventSystem.emit("exitGraffitiMode")
            end
        end
    end
end

function GameStateSystem:enterGraffitiMode(billboardActor, playerX, playerY)
    -- Get game state component
    local stateActors = self.world:getActorsWithComponent(GameStateComponent)
    if #stateActors == 0 then return end
    
    local gameState = stateActors[1]:getComponent(GameStateComponent)
    
    -- Store current state information
    gameState.currentState = "graffiti"
    gameState.activeBillboard = billboardActor
    gameState.playerPosition = {x = playerX, y = playerY}
    
    -- Hide platformer elements by moving them offscreen
    self:togglePlatformerVisibility(false)
    
    -- Setup spray painting game
    setupSprayPaintingGame(self.world)
    
    -- Reset camera draw offset to show only the graffiti canvas
    playdate.graphics.setDrawOffset(0, 0)
    
    print("Entered graffiti mode")
end

function GameStateSystem:togglePlatformerVisibility(visible)
    -- Hide or show platformer elements
    local platforms = self.world:getActorsWithComponent(PlatformComponent)
    local players = self.world:getActorsWithComponent(PlayerComponent)
    local walls = self.world:getActorsWithComponent(WallComponent)
    local billboards = self.world:getActorsWithComponent(BillboardComponent)
    
    -- Get all platformer UI
    local platformerUI = {}
    for _, actor in ipairs(self.world.actors) do
        if actor:hasComponent(UISystem) then
            table.insert(platformerUI, actor)
        end
    end
    
    local zValue = visible and 10 or -5000  -- Move offscreen when not visible
    
    -- Set visibility for platforms
    for _, actor in ipairs(platforms) do
        actor:setZIndex(visible and 10 or -5000)
        actor:setVisible(visible)
    end
    
    -- Set visibility for walls
    for _, actor in ipairs(walls) do
        actor:setZIndex(visible and 10 or -5000)
        actor:setVisible(visible)
    end
    
    -- Set visibility for player
    for _, actor in ipairs(players) do
        actor:setZIndex(visible and 100 or -5000)
        actor:setVisible(visible)
    end
    
    -- Set visibility for billboards
    for _, actor in ipairs(billboards) do
        actor:setZIndex(visible and 5 or -5000)
        actor:setVisible(visible)
    end
    
    -- Set visibility for platformer UI (if any)
    for _, actor in ipairs(platformerUI) do
        actor:setVisible(visible)
    end
end

function GameStateSystem:exitGraffitiMode()
    -- Get game state component
    local stateActors = self.world:getActorsWithComponent(GameStateComponent)
    if #stateActors == 0 then return end
    
    local gameState = stateActors[1]:getComponent(GameStateComponent)
    
    -- Clean up any graffiti mode actors
    local actorsToRemove = {}
    
    local canvasActors = self.world:getActorsWithComponent(CanvasComponent)
    local sprayActors = self.world:getActorsWithComponent(SprayCanComponent)
    local uiActors = self.world:getActorsWithComponent(GraffitiUIComponent)
    
    for _, actor in ipairs(canvasActors) do table.insert(actorsToRemove, actor) end
    for _, actor in ipairs(sprayActors) do table.insert(actorsToRemove, actor) end
    for _, actor in ipairs(uiActors) do table.insert(actorsToRemove, actor) end
    
    for _, actor in ipairs(actorsToRemove) do
        self.world:removeActor(actor)
    end
    
    -- Show platformer elements again
    self:togglePlatformerVisibility(true)
    
    -- Restore platformer mode
    gameState.currentState = "platformer"
    
    -- Find the camera component to restore proper camera view
    local cameras = self.world:getActorsWithComponent(CameraComponent)
    if #cameras > 0 then
        local camera = cameras[1]:getComponent(CameraComponent)
        if camera then
            -- Force update to restore camera position
            camera:update()
        end
    end
    
    print("Exited graffiti mode")
end

function GameStateSystem:saveGraffiti(canvasImage)
    -- Get game state component
    local stateActors = self.world:getActorsWithComponent(GameStateComponent)
    if #stateActors == 0 then return end
    
    local gameState = stateActors[1]:getComponent(GameStateComponent)
    if not gameState.activeBillboard then return end
    
    -- Create a scaled-down version of the graffiti
    local billboard = gameState.activeBillboard:getComponent(BillboardComponent)
    local scaledSize = math.min(billboard.width - 6, billboard.height - 6)
    
    -- Create a new image that's a scaled version of the canvas
    local scaledImage = gfx.image.new(scaledSize, scaledSize)
    gfx.pushContext(scaledImage)
    canvasImage:drawScaled(0, 0, scaledSize/400)
    gfx.popContext()
    
    -- Update the billboard with the new graffiti image
    billboard:setGraffitiImage(scaledImage)
    
    print("Saved graffiti to billboard")
end

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
            -- Debug output when direction changes
            print("Facing left (-1)")
        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
            moveInput = 1
            player.facingDirection = 1
            -- Debug output when direction changes
            print("Facing right (1)")
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
                if moveInput ~= 0 then
                    -- Only override velocity with direct control when actively moving
                    physics:setVelocity(moveInput * player.moveSpeed, physics.velocity.y)
                end
                -- When no input, let friction handle deceleration
            else
                -- Air control is slightly less responsive
                if player.isAgainstWall and moveInput == player.wallDirection then
                    -- Don't push into the wall
                    physics:setVelocity(0, physics.velocity.y)
                else
                    -- Apply force in air rather than setting velocity directly
                    -- This allows for smoother deceleration with air friction
                    physics:setVelocity(
                        physics.velocity.x + moveInput * (player.moveSpeed * 0.3),
                        physics.velocity.y
                    )
                    -- Cap horizontal air speed
                    physics.velocity.x = math.max(-player.moveSpeed, math.min(player.moveSpeed, physics.velocity.x))
                end
            end

            -- Wall slide - only apply for falling, not when moving upward
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

        -- Dash - either with Down+B or just B-press if in dash end lag
        if (playdate.buttonJustPressed(playdate.kButtonDown) and playdate.buttonIsPressed(playdate.kButtonB)) or 
           (playdate.buttonJustPressed(playdate.kButtonB) and not player.isClimbing) then
            
            -- Only process dash input if not in dash end lag
            if not player.dashEndLagTimer then
                -- Get dash direction options
                local dashDirX = 0
                local dashDirY = 0
                
                -- Try to get direction from d-pad first
                if playdate.buttonIsPressed(playdate.kButtonUp) and not playdate.buttonIsPressed(playdate.kButtonDown) then
                    dashDirY = -1
                elseif playdate.buttonIsPressed(playdate.kButtonDown) and not playdate.buttonIsPressed(playdate.kButtonUp) then
                    dashDirY = 1
                end
                
                if playdate.buttonIsPressed(playdate.kButtonLeft) and not playdate.buttonIsPressed(playdate.kButtonRight) then
                    dashDirX = -1
                elseif playdate.buttonIsPressed(playdate.kButtonRight) and not playdate.buttonIsPressed(playdate.kButtonLeft) then
                    dashDirX = 1
                end
                
                -- If no direction from d-pad, check crank
                if dashDirX == 0 and dashDirY == 0 then
                    -- Get dash direction from crank position only if crank has been turned
                    local crankPos = playdate.getCrankPosition()
                    local crankChange = playdate.getCrankChange()
                    
                    -- Only use crank if it has been moved recently (indicating intentional use)
                    if math.abs(crankChange) > 0.1 then
                        dashDirX = math.cos(math.rad(crankPos))
                        dashDirY = math.sin(math.rad(crankPos))
                        print("Using crank for dash direction: " .. dashDirX .. ", " .. dashDirY)
                    end
                end
                
                -- If still no direction, use the player's facing direction
                if dashDirX == 0 and dashDirY == 0 then
                    -- Always use player's facing direction as a reliable default
                    dashDirX = player.facingDirection
                    dashDirY = 0
                    
                    -- Debug output to verify dash direction
                    print("Default dash direction: " .. dashDirX .. ", " .. dashDirY)
                end
                
                player:startDash(dashDirX, dashDirY)
            end
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
            -- Apply friction to X velocity based on ground/air state
            physics:applyFriction()
            
            -- Apply gravity
            physics.velocity.y = physics.velocity.y + physics.gravity

            -- Avoid very tiny movements that could cause vibration
            if math.abs(physics.velocity.y) < 0.01 then
                physics.velocity.y = 0
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
        physics.isOnGround = false
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
                physics.isOnGround = true

                -- Don't completely zero vertical velocity, reduce it significantly
                physics.velocity.y = physics.velocity.y * 0.1

                -- Reset jump state when grounded
                if not playdate.buttonIsPressed(playdate.kButtonA) then
                    player.isJumping = false
                end

                -- Reset dash ability when landing
                player.canDash = true
                player.hasDashed = false     -- Reset air dash flag
                player.dashRefreshedByGround = true
            elseif normalY == 1 then -- Hit ceiling
                -- Zero out upward velocity when hitting ceiling
                if physics.velocity.y < 0 then
                    physics.velocity.y = 0
                end
            elseif normalX ~= 0 then -- Hit a wall
                player.isAgainstWall = true
                player.wallDirection = normalX

                -- Apply wall friction based on player input
                if player.isClimbing then
                    -- When climbing, no sliding
                    physics.velocity.y = 0
                else
                    -- If falling, apply wall friction. Don't affect upward momentum
                    if physics.velocity.y > 0 then
                        -- Check if player is pushing into the wall
                        local moveInput = 0
                        if playdate.buttonIsPressed(playdate.kButtonLeft) then
                            moveInput = -1
                        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
                            moveInput = 1
                        end
                        
                        -- If pushing into wall, apply more friction (reduce gravity effect) only when falling
                        if moveInput == normalX then
                            -- Strong wall friction when pushing into it while falling
                            physics.velocity.y = physics.velocity.y * player.wallFrictionMultiplier
                        else
                            -- Normal wall sliding when falling
                            physics.velocity.y = player.wallSlideSpeed
                        end
                    end
                    -- Don't modify upward velocity when hitting a wall horizontally
                    -- This allows the player to maintain their jump momentum
                end
            end
        else
            -- If not collided, we're not on ground
            physics.isOnGround = false
        end
        
        -- Apply friction to player movement
        physics:applyFriction()

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
        self:createBillboards()
        self.isLevelCreated = true
    end
end

function LevelSystem:createBillboards()
    -- Create billboards for graffiti mode
    self:createBillboard(150, 125, 40, 30)
    self:createBillboard(300, 45, 40, 30)
    
    print("Billboards created")
end

function LevelSystem:createBillboard(x, y, width, height)
    local billboardActor = Actor()
    billboardActor:addComponent(TransformComponent, x, y)
    billboardActor:addComponent(BillboardComponent, width, height)
    self.world:addActor(billboardActor)
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

    -- Create more particles for a more impactful dash effect
    local particleCount = 15
    
    -- Create a more varied trail of particles
    for _ = 1, particleCount do
        local particleActor = Actor()

        -- Create particles with varied shapes and sizes
        local particleType = math.random(1, 3)
        local particleSize = math.random(2, 6)
        local particleImage = gfx.image.new(particleSize, particleSize)
        
        gfx.pushContext(particleImage)
        gfx.setColor(gfx.kColorWhite)
        
        -- Different particle shapes for variety
        if particleType == 1 then
            -- Square
            gfx.fillRect(0, 0, particleSize, particleSize)
        elseif particleType == 2 then
            -- Circle
            gfx.fillCircleAtPoint(particleSize/2, particleSize/2, particleSize/2)
        else
            -- Diamond
            gfx.fillTriangle(
                particleSize/2, 0,
                particleSize, particleSize/2,
                particleSize/2, particleSize)
            gfx.fillTriangle(
                particleSize/2, 0,
                0, particleSize/2,
                particleSize/2, particleSize)
        end
        
        gfx.popContext()

        particleActor:setImage(particleImage)
        particleActor:setZIndex(90)

        -- Ensure we have valid direction values
        local safeDirX = dirX or 0
        local safeDirY = dirY or 0
        
        -- More spread out particles along the dash path
        local perpX = -(safeDirY) -- Perpendicular to dash direction
        local perpY = safeDirX
        
        -- Position particles along and around the dash path
        local mainOffset = math.random(-10, 10)
        local perpOffset = math.random(-8, 8)
        local offsetX = (mainOffset * safeDirX) + (perpOffset * perpX)
        local offsetY = (mainOffset * safeDirY) + (perpOffset * perpY)

        -- Velocity with more variation and opposing the dash direction for a trail effect
        local speedVariation = math.random(80, 150) / 100
        -- For random floats in range, use math.random() * range + min
        local vx = -safeDirX * speedVariation + (math.random() - 0.5) -- Random value between -0.5 and 0.5
        local vy = -safeDirY * speedVariation + (math.random() - 0.5) -- Random value between -0.5 and 0.5

        -- Shorter but more varied lifetimes
        local lifetime = math.random(200, 400) -- These should be integers

        particleActor:addComponent(TransformComponent, transform.x + offsetX, transform.y + offsetY)
        particleActor:addComponent(ParticleComponent, lifetime, vx, vy)

        self.world:addActor(particleActor)
    end
    
    -- Add a "dash line" effect in the direction of the dash
    local dashLineActor = Actor()
    local lineLength = 16
    local lineWidth = 4
    
    -- Calculate line start and end points based on dash direction
    local safeDirX = dirX or 0
    local safeDirY = dirY or 0
    
    local startX = transform.x
    local startY = transform.y
    local endX = startX + (safeDirX * lineLength)
    local endY = startY + (safeDirY * lineLength)
    
    -- Create a line image
    local angle = math.atan2(safeDirY, safeDirX)
    local lineImage = gfx.image.new(lineLength + lineWidth, lineWidth * 2)
    
    gfx.pushContext(lineImage)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, lineWidth/2, lineLength, lineWidth)
    gfx.popContext()
    
    dashLineActor:setImage(lineImage)
    dashLineActor:setZIndex(95)
    dashLineActor:setRotation(math.deg(angle))
    
    dashLineActor:addComponent(TransformComponent, (startX + endX) / 2, (startY + endY) / 2)
    dashLineActor:addComponent(ParticleComponent, 100, 0, 0) -- Short lifetime for the line effect
    
    self.world:addActor(dashLineActor)
end

function ParticleSystem:update()
    -- Particles update themselves via their timers
end

-- ==========================================
-- Graffiti Mode Components and Systems
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

class('GraffitiUIComponent').extends(Component)

function GraffitiUIComponent:init(actor)
    GraffitiUIComponent.super.init(self, actor)
    self.uiImage = gfx.image.new(400, 240)
    self.actor:setImage(self.uiImage)
    self.actor:setZIndex(90)              -- Below cursor but above canvas
    self.actor:setIgnoresDrawOffset(true) -- UI stays fixed on screen
end

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

        -- Press A+Down to clear canvas
        if playdate.buttonJustPressed(playdate.kButtonA) and playdate.buttonIsPressed(playdate.kButtonDown) then
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
        if playdate.buttonIsPressed(playdate.kButtonA) and not playdate.buttonIsPressed(playdate.kButtonDown) and sprayCan.pressure > 0 then
            self:applySpray(canvas, transform.x, transform.y, sprayCan)
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

class('GraffitiUISystem').extends(System)

function GraffitiUISystem:update()
    local uiActors = self.world:getActorsWithComponent(GraffitiUIComponent)
    if #uiActors == 0 then return end

    local ui = uiActors[1]:getComponent(GraffitiUIComponent)
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
    gfx.drawTextAligned("D-Pad: Move   A: Spray   A+Down: Clear   B: Exit", 200, 220, kTextAlignment.center)

    gfx.popContext()
    ui.actor:markDirty()
end

-- Function to setup the graffiti minigame
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
    uiActor:addComponent(GraffitiUIComponent)
    world:addActor(uiActor)

    -- Add spray systems to world
    world:addSystem(SprayInputSystem())
    world:addSystem(SpraySystem())
    world:addSystem(DripSystem())
    world:addSystem(GraffitiUISystem())
    
    print("Spray Painting Game initialized")
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
    gfx.fillRect(50, 165, 300, 70)
    gfx.setDitherPattern(0)
    -- Draw text
    gfx.setColor(gfx.kColorWhite)
    gfx.drawTextAligned("CONTROLS:", 200, 170, kTextAlignment.center)
    gfx.drawTextAligned("D-Pad: Move   A: Jump   B: Climb", 200, 190, kTextAlignment.center)
    gfx.drawTextAligned("B: Dash (use D-pad to aim)", 200, 210, kTextAlignment.center)
    gfx.drawTextAligned("Air dash resets when landing or on walls", 200, 230, kTextAlignment.center)
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
    -- Create game state actor first
    local gameStateActor = Actor()
    gameStateActor:addComponent(GameStateComponent)
    gameWorld:addActor(gameStateActor)
    
    -- Initialize celeste platformer
    setupCelesteGame(gameWorld)
    
    -- Add game state system
    gameWorld:addSystem(GameStateSystem())
    
    print("Game initialized with both platformer and graffiti modes")
end

-- Initialize game
playdate.gameWillStart()