local vector     = require "lib.vec3"
local fam        = require "fam"
local dialog     = require "dialog"
local permanence = require "permanence"
local assets     = require "assets"
local language   = require "language"

local global     = permanence.data

-- TODO: implement scene scripting language? CODENAME: MIKAMO

local play_sound = function(snd, volume, pitch)
    snd:stop()
    snd:setVolume(volume or 1)
    snd:setPitch(pitch or 1)
    snd:play()

    while snd:isPlaying() do
        coroutine.yield()
    end
end

return {
    passthrough = function(entity, dt, state)
        entity:passthrough_routine(dt, state)
    end,

    dialog_passthrough = function(entity, dt, state)
        -- UNUSED
    end
}
