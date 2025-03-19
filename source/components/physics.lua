class('PhysicsComponent').extends(Component)

function PhysicsComponent:init(actor, gravity, width, height)
    PhysicsComponent.super.init(self, actor)
    self.gravity = gravity or 0.35
    self.velocity = { x = 0, y = 0 }
    self.width = width or 16
    self.height = height or 16
    self.isColliding = false
    
    -- Friction properties
    self.groundFriction = 0.85  -- Higher value = more friction on ground
    self.airFriction = 0.97     -- Higher value = less friction in air
    self.isOnGround = false     -- Track if entity is on ground
    
    -- Collision properties
    self.collisionRect = { x = 0, y = 0, width = self.width, height = self.height }

    -- Store remaining movement when collision occurs
    self.remainingMovementX = 0
    self.remainingMovementY = 0
end

function PhysicsComponent:updateCollisionRect()
    local transform = self.actor:getComponent(TransformComponent)
    if transform then
        -- Update collision rect based on transform position
        self.collisionRect.x = transform.x - self.width / 2
        self.collisionRect.y = transform.y - self.height / 2
    end
end

function PhysicsComponent:setVelocity(x, y)
    self.velocity.x = x
    self.velocity.y = y
end

function PhysicsComponent:applyFriction()
    -- Apply different friction based on whether the entity is on ground or in air
    if self.isOnGround then
        -- Apply ground friction (higher)
        self.velocity.x = self.velocity.x * self.groundFriction
    else
        -- Apply air friction (lower)
        self.velocity.x = self.velocity.x * self.airFriction
    end
    
    -- Prevent tiny movements by zeroing out very small velocities
    if math.abs(self.velocity.x) < 0.01 then
        self.velocity.x = 0
    end
end

function PhysicsComponent:moveWithCollision(platforms, walls)
    local transform = self.actor:getComponent(TransformComponent)
    if not transform then return false, nil, 0, 0 end

    -- Cache original position
    local originalX = transform.x
    local originalY = transform.y

    -- Apply horizontal movement first
    transform:setPosition(originalX + self.velocity.x, originalY)
    self:updateCollisionRect()

    -- Check and resolve horizontal collisions
    local xCollision = false
    local xNormal = 0
    local xCollider = nil
    local xColliderType = nil

    -- Check all platforms and walls
    for _, platform in ipairs(platforms) do
        if self:checkCollisionWithEntity(platform) then
            xCollision = true
            xCollider = platform
            xColliderType = "platform"
            xNormal = (self.velocity.x > 0) and -1 or 1
            -- Move back to original X position
            transform:setPosition(originalX, originalY)
            break
        end
    end

    if not xCollision then
        for _, wall in ipairs(walls) do
            if self:checkCollisionWithEntity(wall) then
                xCollision = true
                xCollider = wall
                xColliderType = "wall"
                xNormal = (self.velocity.x > 0) and -1 or 1
                -- Move back to original X position
                transform:setPosition(originalX, originalY)
                break
            end
        end
    end

    -- Now apply vertical movement from current position
    local currentX = transform.x
    transform:setPosition(currentX, originalY + self.velocity.y)
    self:updateCollisionRect()

    -- Check and resolve vertical collisions
    local yCollision = false
    local yNormal = 0
    local yCollider = nil
    local yColliderType = nil

    for _, platform in ipairs(platforms) do
        if self:checkCollisionWithEntity(platform) then
            yCollision = true
            yCollider = platform
            yColliderType = "platform"
            yNormal = (self.velocity.y > 0) and -1 or 1
            -- Move back to safe Y position
            transform:setPosition(currentX, originalY)
            break
        end
    end

    if not yCollision then
        for _, wall in ipairs(walls) do
            if self:checkCollisionWithEntity(wall) then
                yCollision = true
                yCollider = wall
                yColliderType = "wall"
                yNormal = (self.velocity.y > 0) and -1 or 1
                -- Move back to safe Y position
                transform:setPosition(currentX, originalY)
                break
            end
        end
    end

    -- Determine collision result
    local collided = xCollision or yCollision
    local collider = yCollider or xCollider
    local colliderType = yColliderType or xColliderType
    local normalX = xNormal
    local normalY = yNormal

    return collided, collider, normalX, normalY, colliderType
end

function PhysicsComponent:checkCollisionWithEntity(entity)
    -- Get necessary components from the target entity
    local entityTransform = entity:getComponent(TransformComponent)
    local entityWidth, entityHeight

    if entity:hasComponent(PlatformComponent) then
        local platformComponent = entity:getComponent(PlatformComponent)
        entityWidth = platformComponent.width
        entityHeight = platformComponent.height
    elseif entity:hasComponent(WallComponent) then
        local wallComponent = entity:getComponent(WallComponent)
        entityWidth = wallComponent.width
        entityHeight = wallComponent.height
    else
        return false
    end

    -- Calculate entity collision rect
    local entityRect = {
        x = entityTransform.x - entityWidth / 2,
        y = entityTransform.y - entityHeight / 2,
        width = entityWidth,
        height = entityHeight
    }

    -- Check for AABB collision
    return self:rectsIntersect(self.collisionRect, entityRect)
end

-- Add a simple AABB collision check method
function PhysicsComponent:checkCollision(platforms, walls)
    local hitPlatform, hitWall = nil, nil

    -- Check platforms
    for _, platform in ipairs(platforms) do
        local platformComponent = platform:getComponent(PlatformComponent)
        local platformTransform = platform:getComponent(TransformComponent)

        if platformComponent and platformTransform then
            local platformRect = {
                x = platformTransform.x - platformComponent.width / 2,
                y = platformTransform.y - platformComponent.height / 2,
                width = platformComponent.width,
                height = platformComponent.height
            }

            if self:rectsIntersect(self.collisionRect, platformRect) then
                hitPlatform = platform
                break
            end
        end
    end

    -- Check walls
    for _, wall in ipairs(walls) do
        local wallComponent = wall:getComponent(WallComponent)
        local wallTransform = wall:getComponent(TransformComponent)

        if wallComponent and wallTransform then
            local wallRect = {
                x = wallTransform.x - wallComponent.width / 2,
                y = wallTransform.y - wallComponent.height / 2,
                width = wallComponent.width,
                height = wallComponent.height
            }

            if self:rectsIntersect(self.collisionRect, wallRect) then
                hitWall = wall
                break
            end
        end
    end

    return hitPlatform, hitWall
end

function PhysicsComponent:rectsIntersect(rect1, rect2)
    return not (
        rect1.x + rect1.width <= rect2.x or
        rect1.x >= rect2.x + rect2.width or
        rect1.y + rect1.height <= rect2.y or
        rect1.y >= rect2.y + rect2.height
    )
end

CollisionUtils = {}

-- Swept AABB collision detection
-- Returns the time of collision and the normal of the collision surface
function CollisionUtils.sweepAABB(movingRect, staticRect, velocityX, velocityY)
    -- Check if already overlapping, in which case we return immediate collision
    local overlapping = (
        movingRect.x < staticRect.x + staticRect.width and
        movingRect.x + movingRect.width > staticRect.x and
        movingRect.y < staticRect.y + staticRect.height and
        movingRect.y + movingRect.height > staticRect.y
    )

    if overlapping then
        -- Determine push direction for already overlapping objects
        local overlapX = 0
        local overlapY = 0

        if velocityX > 0 then
            overlapX = (staticRect.x + staticRect.width) - movingRect.x
        else
            overlapX = staticRect.x - (movingRect.x + movingRect.width)
        end

        if velocityY > 0 then
            overlapY = (staticRect.y + staticRect.height) - movingRect.y
        else
            overlapY = staticRect.y - (movingRect.y + movingRect.height)
        end

        -- Return minimum (non-zero) time and appropriate normal
        if math.abs(overlapX) < math.abs(overlapY) then
            return 0, (overlapX > 0) and -1 or 1, 0
        else
            return 0, 0, (overlapY > 0) and -1 or 1
        end
    end

    local xInvEntry, yInvEntry
    local xInvExit, yInvExit

    -- Find the distance between the objects on the near and far sides for both x and y
    if velocityX > 0 then
        xInvEntry = staticRect.x - (movingRect.x + movingRect.width)
        xInvExit = (staticRect.x + staticRect.width) - movingRect.x
    else
        xInvEntry = (staticRect.x + staticRect.width) - movingRect.x
        xInvExit = staticRect.x - (movingRect.x + movingRect.width)
    end

    if velocityY > 0 then
        yInvEntry = staticRect.y - (movingRect.y + movingRect.height)
        yInvExit = (staticRect.y + staticRect.height) - movingRect.y
    else
        yInvEntry = (staticRect.y + staticRect.height) - movingRect.y
        yInvExit = staticRect.y - (movingRect.y + movingRect.height)
    end

    -- Find time of collision and time of leaving for each axis
    local xEntry, yEntry
    local xExit, yExit

    if velocityX == 0 then
        xEntry = -math.huge
        xExit = math.huge
    else
        xEntry = xInvEntry / velocityX
        xExit = xInvExit / velocityX
    end

    if velocityY == 0 then
        yEntry = -math.huge
        yExit = math.huge
    else
        yEntry = yInvEntry / velocityY
        yExit = yInvExit / velocityY
    end

    -- Find the earliest/latest times of collision
    local entryTime = math.max(xEntry, yEntry)
    local exitTime = math.min(xExit, yExit)

    -- If there's no collision
    if entryTime > exitTime or (xEntry < 0 and yEntry < 0) or entryTime > 1 then
        return 1, 0, 0 -- Return no collision (t=1)
    end

    -- Calculate normal of collided surface
    local normalX, normalY = 0, 0

    if xEntry > yEntry then
        if xInvEntry < 0 then
            normalX = 1
            normalY = 0
        else
            normalX = -1
            normalY = 0
        end
    else
        if yInvEntry < 0 then
            normalX = 0
            normalY = 1
        else
            normalX = 0
            normalY = -1
        end
    end

    -- Return the time of collision, and the collision normal
    return entryTime, normalX, normalY
end
