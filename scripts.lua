local vector = require "lib.vec3"
local fam = require "fam"

return {
    conga_man = function (entity, dt, state)
        entity.velocity = vector(-1, 0, 0)
        fam.wait(1)
        
        while true do
            entity.velocity = vector(1, 0, 0)
            fam.wait(2)
            entity.velocity = vector(-1, 0, 0)
            fam.wait(2)
        end
    end
}