local vector = require "lib.vec3"
local fam = require "fam"
local dialog = require "dialog"

return {
    conga_man = function (entity, dt, state)
        local timer = 0
        while true do
            timer = timer + dt * 0.2
            entity.flip_x = (math.floor(timer)%2)==1 and 1 or -1
            coroutine.yield()
        end
    end,

    campfire = function (entity, dt, state)
        entity.interact_amount = (entity.interact_amount or 0) + 1

        if entity.interact_amount == 3 then
            dialog:say("\n* enough conga.")
            entity.delete = true
            return
        end

        dialog:say("* CONGA CONGA CONGA, \n* DON'T-A STOP THE CONGA!")
        dialog:say("* CONGA CONGA CONGA, \n* VAMOS A BAILAR!")
        entity.scale.y = entity.scale.y * 1.1
    end,

    test0 = function (entity, dt, state)
        entity.sprite = { 0, 32, 32, 32 }
        entity.scale = vector(1, 1, 1)
        entity.interact = "campfire"
        entity.routine = "conga_man"
    end
}