local vector     = require "lib.vec3"
local fam        = require "fam"
local dialog     = require "dialog"
local permanence = require "permanence"
local assets     = require "assets"
local language   = require "language"
local missions   = require "missions"

local global = {}

local play_sound = function (snd, volume, pitch)
    snd:stop()
    snd:setVolume(volume or 1)
    snd:setPitch(pitch or 1)
    snd:play()
    
    while snd:isPlaying() do
        coroutine.yield()
    end
end

return {
    passthrough = function (entity, dt, state)
        entity:passthrough_routine(dt, state)
    end,

    dialog_passthrough = function (entity, dt, state)
        
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

    catboy_lost_his_yoyo = function (entity, dt, state)
        entity.scale = vector(1, 1, 1)
        entity.sprite = { 0, 0, 56, 56 }
        entity.atlas = assets.tex_catboy
        entity.interact = "passthrough"
        entity.flip_x = 1

        local final = function ()
            entity.sprite[1] = 0
            entity.sprite[2] = 56
            entity.flip_x = -entity.flip_x
            dialog:say "* Thanks for finding my yoyo :)\n\n\n\n   ^~dōmo arigatō gozaimasu!!!!"
        end

        entity.passthrough_routine = function ()
            if global.has_yoyo then
                entity.sprite[1] = 112
                dialog:say("* why do you have my yoyo.")
                dialog:say("* give it to me.")

                entity.passthrough_routine = final
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

                    entity.sprite[1] = 56
                    entity.flip_x = -entity.flip_x

                    play_sound(assets.sfx_wow, 0.7)
                    dialog:say("* WOW YOU FOUND MY YOYO????")
                    entity.flip_x = -entity.flip_x

                    play_sound(assets.sfx_wow, 0.7, 1.2)
                    dialog:say("* OH MEIN GOTT\n* CECI EST INCROYABLE\n* ~ABSOLUTE DESPACITO MOMENTO\n\n~^(very cool)")
                    entity.flip_x = -entity.flip_x
                    entity.sprite[1] = 112
                    dialog:say("* it's fine.")
                    entity.sprite[1] = 0

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
            global.has_yoyo = true
            missions:remove("catboy_yoyo0")
            if global.talked_to_yoyoboy then
                missions:add("Give him the Yoyo.", "catboy_yoyo1")
            end
            entity.invisible = true

            play_sound(assets.sfx_tada)
            dialog:say("~You found the ^Yoyo!")
            entity.delete = true
        end
    end
}