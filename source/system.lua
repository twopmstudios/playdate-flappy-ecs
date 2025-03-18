class('System').extends()

function System:init(world)
    self.world = world
    self.dependencies = {} -- Systems that must run before this one
    self.dependents = {}   -- Systems that depend on this one
    self.priority = 0      -- Calculated priority (internal use)

    -- Get the class name safely
    local classInfo = getmetatable(self)
    self.name = classInfo and classInfo.__name or "UnknownSystem"
end

function System:dependsOn(system)
    if system then
        table.insert(self.dependencies, system)
        table.insert(system.dependents, self)
    end
    return self -- Allow chaining
end

function System:update() end
