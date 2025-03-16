-- ==========================================
-- System Base Class
-- ==========================================
class('System').extends()

function System:init(world)
    self.world = world
end

function System:update() end
