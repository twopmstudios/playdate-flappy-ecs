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
        actor:remove() -- Remove from Playdate sprite system
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
