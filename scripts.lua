local vector     = require "lib.vec3"
local fam        = require "fam"
local dialog     = require "dialog"
local permanence = require "permanence"
local assets     = require "assets"
local language   = require "language"

return {
    conga_man = function (entity, dt, state)
        local timer = 0
        entity.flip_x = 1
        while true do
            timer = timer + dt * 0.2
            if timer > 1 then
                entity.flip_x = -entity.flip_x
                timer = 0
            end
            coroutine.yield()
        end
    end,

    campfire = function (entity, dt, state)
        entity.interact_amount = (entity.interact_amount or 0) + 1

        if entity.interact_amount == 3 then
            dialog:say(language.NPC_CONGA_MAN02, 0.7, true)

            assets.mus_prism:setVolume(0.1)
            assets.mus_prism:setLooping(true)
            assets.mus_prism:setPitch(0.8)
            assets.mus_prism:play()
            
            table.insert(state.new_entities, { name = "npc/wait_and_close" })

            entity.delete = true
            return
        end

        dialog:say(language.NPC_CONGA_MAN00)
        entity.flip_x = -entity.flip_x
        dialog:say(language.NPC_CONGA_MAN01)
        entity.scale.y = entity.scale.y * 1.1
    end,

    wait_and_close = function ()
        fam.wait(15)
        assets.mus_prism:setPitch(0.5)
        os.execute("zenity --error --text=\"[ERROR] main.lua:462: No more space!\"")
        love.event.quit()
    end,

    test0 = function (entity, dt, state)
        entity.sprite = { 0, 32, 32, 32 }
        entity.scale = vector(1, 1, 1)
        entity.interact = "campfire"
        entity.routine = "conga_man"
    end
}