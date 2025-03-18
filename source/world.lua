class('World').extends()

function World:init()
    self.actors = {}
    self.systems = {}
    self.systemsByName = {} -- For easy lookup
    self.active = false
    self.isDirty = true     -- If true, recalculate system order
end

function World:addActor(actor)
    self.actors[actor.id] = actor
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
    -- Add system to the list
    table.insert(self.systems, system)

    -- Initialize the system
    if not system.world then -- Only initialize if not already initialized
        system:init(self)
    end

    -- Get system name safely
    local name = system.name or "System_" .. #self.systems
    system.name = name -- Ensure system has name property

    -- Store for lookup by name
    self.systemsByName[name] = system

    -- Mark as needing recalculation
    self.isDirty = true

    return system
end

function World:setupDependency(systemA, systemB)
    -- Make systemB depend on systemA (A runs before B)
    local sysA = systemA
    local sysB = systemB

    if type(systemA) == "string" then
        sysA = self.systemsByName[systemA]
    end

    if type(systemB) == "string" then
        sysB = self.systemsByName[systemB]
    end

    if sysA and sysB then
        sysB:dependsOn(sysA)
        self.isDirty = true -- Need to recalculate order
    else
        print("Warning: Could not set up dependency between",
            systemA, "and", systemB,
            "- one or both systems not found")
    end

    return self -- Allow chaining
end

function World:calculateSystemOrder()
    if #self.systems <= 1 then
        self.isDirty = false
        return -- Nothing to calculate with 0-1 systems
    end

    -- First reset priorities
    for _, system in ipairs(self.systems) do
        system.priority = 0
        system.visited = false
    end

    -- Depth-first traversal to calculate priorities
    local function visit(system, depth)
        if system.visited then return end
        system.visited = true

        -- First process all dependencies
        for _, dependency in ipairs(system.dependencies or {}) do
            visit(dependency, depth + 1)
        end

        -- Ensure this system has higher priority than dependencies
        for _, dependency in ipairs(system.dependencies or {}) do
            if dependency.priority >= system.priority then
                system.priority = dependency.priority + 1
            end
        end
    end

    -- Visit all systems
    for _, system in ipairs(self.systems) do
        visit(system, 0)
    end

    -- Sort systems by priority
    table.sort(self.systems, function(a, b)
        return a.priority < b.priority
    end)

    -- Clean up temporary flags
    for _, system in ipairs(self.systems) do
        system.visited = nil
    end

    -- Debug output
    print("System execution order:")
    for i, system in ipairs(self.systems) do
        print(i .. ": " .. (system.name or "UnnamedSystem") .. " (priority: " .. system.priority .. ")")
    end

    self.isDirty = false
end

function World:update()
    if not self.active then return end

    -- Recalculate system order if needed
    if self.isDirty then
        self:calculateSystemOrder()
    end

    -- Update systems in priority order
    for _, system in ipairs(self.systems) do
        system:update()
    end
end

function World:start()
    self.active = true
    -- Calculate initial system order
    self:calculateSystemOrder()
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
