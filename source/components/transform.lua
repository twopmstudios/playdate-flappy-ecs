import "../component"

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
