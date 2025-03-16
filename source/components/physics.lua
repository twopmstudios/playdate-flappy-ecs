class('PhysicsComponent').extends(Component)

function PhysicsComponent:init(actor, gravity, width, height)
    PhysicsComponent.super.init(self, actor)
    self.velocity = { x = 0, y = 0 }
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
