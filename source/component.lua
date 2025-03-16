-- ==========================================
-- Component System
-- ==========================================
class('Component').extends()

function Component:init(actor)
    self.actor = actor
end

function Component:update() end

function Component:onAdd() end

function Component:onRemove() end
