local vector     = require "lib.vec3"
local fam        = require "fam"
local dialog     = require "dialog"
local permanence = require "permanence"
local assets     = require "assets"
local language   = require "language"
local missions   = require "missions"

local global = {}

return {
    passthrough = function (entity, dt, state)
        entity:passthrough_routine(dt, state)
    end,

    dialog_passthrough = function (entity, dt, state)
        
    end,

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
    end,

    catboy_lost_his_yoyo = function (entity, dt, state)
        entity.scale = vector(1, 1, 1)
        entity.sprite = { 0, 0, 56, 56 }
        entity.atlas = assets.tex_catboy
        entity.interact = "passthrough"
        entity.flip_x = 1

        local final = function ()
            dialog:say "* Thanks for finding my yoyo :)"
        end

        entity.passthrough_routine = function ()
            if global.has_yoyo then
                dialog:say("* why do you have my yoyo.")
                dialog:say("* give it to me.")

                entity.passthrough_routine = final
                final()
                return
            end

            global.talked_to_yoyoboy = true

            entity.flip_x = -entity.flip_x
            local select = dialog:ask("* i lost my ^yoyo^ :(\n* could you help me find it?", {"yeah", "nope"})
            entity.flip_x = -entity.flip_x
            if select == 1 then
                dialog:say("* it'd mean a lot to me...")
                missions:add("Find Yoyo", "catboy_yoyo0")
            else
                dialog:say("* it's fine if you cant help me yet...")
            end

            entity.passthrough_routine = function ()
                if global.has_yoyo then
                    missions:remove("catboy_yoyo1")

                    dialog:say("* WOW YOU FOUND MY YOYO????")
                    dialog:say("* OH MEIN GOTT\n* CECI EST INCROYABLE\n* ~ABSOLUTE DESPACITO MOMENTO\n\n~^(very cool)")
                    dialog:say("* it's fine.")

                    entity.passthrough_routine = final
                    final()
                    return
                end
                entity.flip_x = -entity.flip_x
                dialog:say("* thanks for trying...\n")
            end
        end
    end,

    catboy_yoyo = function (entity)
        entity.interact = "passthrough"
        entity.passthrough_routine = function ()
            dialog:say("~You found the ^Yoyo!")
            global.has_yoyo = true
            missions:remove("catboy_yoyo0")
            if global.talked_to_yoyoboy then
                missions:add("Give him the yoyo.", "catboy_yoyo1")
            end
            entity.delete = 1
        end
    end
}