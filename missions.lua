local fam = require "fam"
local assets = require "assets"
local missions = {}

missions.add = function(self, title, key)
    table.insert(self, {
        key = key,
        title = title,
        anim = 0
    })
end

missions.remove = function(self, key)
    for index, what in ipairs(self) do
        if what.key == key then
            self[index] = #self
            self[#self] = nil
            return
        end
    end
end

missions.update = function(self, dt)
    for index, entry in ipairs(self) do
        entry.anim = fam.lerp(entry.anim, 1, 16 * dt)
    end
end

missions.draw = function(self)
    for index, entry in ipairs(self) do
        local w = assets.fnt_main:getWidth(entry.title)
        lg.setColor(fam.hex("#0d0025"))
        lg.rectangle("fill", w * (entry.anim - 1), (13 * index) + 1, w + 2, 12)
        lg.setColor(fam.hex("#dadada"))
        lg.print(entry.title, w * (entry.anim - 1) + 1, 13 * index)
    end
end

return missions
