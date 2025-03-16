import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/ui"
import "CoreLibs/object"
import "CoreLibs/crank"
import "CoreLibs/keyboard"

-- Engine Constants
local gfx <const> = playdate.graphics
local geom <const> = playdate.geometry

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
