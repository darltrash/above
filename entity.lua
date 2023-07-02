local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local input = require "input"
local fam = require "fam"
local scripts = require "scripts"
local slam = require "lib.slam"
local log = require "lib.log"

local assets = require "assets"
local renderer = require "renderer"
local permanence = require "permanence"

---------------------------------------------------------------

local coyote_time = 1 / 8


local initializers = {
    ["player"] = function(entity, state)
        log.info("deer are quite strange actually")

        entity.controller = "player"
        entity.velocity = vector(0, 0, 0)
        entity.scale = vector(0, 0, 0)
        entity.rotation = vector(0, 0, 0)
        entity.camera_target = true

        entity.animation_power = 0
        state.target = entity.position:copy()

        entity.animation = 0
        entity.flip_x = 1
        entity.atlas = assets.tex_hirsch
        entity.collider = {
            offset = vector(0, 0.5, 0),
            radius = vector(0.2, 0.5, 0.1),

            floor_time = 0,
            ceil_time = 0,
            wall_time = 0
        }

        entity.tint = { 1, 1, 1, 1 }

        entity.id = "player"
        entity.offset = vector(0, 0, 0)
        entity.animation_index = 1

        entity.mass = true
    end,

    ["npc"] = function(entity, state, script)
        entity.sprite = { 0, 224, 32, 32 }
        entity.routine = script
        entity.scripts = {}
    end
}

local function init(entities, raw, state)
    local title, numba = raw.name:match("(.+)%.(%d*)")
    title = title or raw.name

    local entity = {
        title = title,
        -- Change Z=1 to Y=1
        position = raw.position and vector(raw.position[1], raw.position[3], -raw.position[2]) or false
    }

    local sections = fam.split(title, "%/")
    local init = initializers[sections[1]]
    if init then
        init(entity, state, unpack(sections, 2))
    end

    if entity.id then
        entities.hash[entity.id] = entity
    end

    table.insert(entities, entity)
end

--------------------------------------------------------------

local PLAYER_ANIMS = { -- 🚶+🦌
    {
        { 0,   0, 56, 56, off = 0 },
        { 56,  0, 56, 56, off = 1 },
        { 0,   0, 56, 56, off = 0 },
        { 112, 0, 56, 56, off = 1 },
    },

    {
        { 0,   56, 56, 56, off = 0 },
        { 56,  56, 56, 56, off = 1 },
        { 0,   56, 56, 56, off = 0 },
        { 112, 56, 56, 56, off = 1 },
    },

    {
        { 0,   112, 56, 56, off = 0 },
        { 112, 112, 56, 56, off = 1 },
    }
}

local controllers = {
    ["player"] = function(entity, dt, state)
        state.player = entity
        local dir = -input:get_direction()

        local velocity = vector(0, 0, 0)

        if (not entity.interacting_with) and require("ui").done then
            velocity = vector(dir.x, 0, dir.y) * 3

            local mag = velocity:magnitude()
            if mag > 0 then
                if math.floor(entity.animation % 2) == 0 then
                    assets.sfx_step:setVolume(lm.random(20, 70) / 100)
                    assets.sfx_step:play()
                end

                if entity.animation == 0 then
                    entity.animation = 1
                end
                entity.animation = entity.animation + dt * mag * 1.2
            else
                entity.animation = 0
            end

            if entity.collider.floor_time > 0 then
                if input.holding("jump") then
                    velocity.y = 10
                    entity.gravity = 0
                end
            end

            if math.abs(dir.x) > 0 then
                --entity.scale.x = 1
                entity.flip_x = -fam.sign(dir.x)
                entity.animation_index = 3
            elseif dir.y > 0 then
                entity.animation_index = 2
            elseif dir.y < 0 then
                entity.animation_index = 1
            end
        end

        if not require("ui").done then
            entity.tint[4] = 0
        else
            entity.tint[4] = fam.lerp(entity.tint[4], 1, dt * 5) + (1 / 8)
        end

        local anim = PLAYER_ANIMS[entity.animation_index]
        entity.sprite = anim[(math.floor(entity.animation) % #anim) + 1]

        entity.scale.y = fam.lerp(entity.scale.y, entity.sprite.sx or 1, dt * 20)

        entity.offset.y = fam.lerp(entity.offset.y, -entity.sprite.off * 0.14, dt * 25)

        entity.velocity = entity.velocity + velocity
    end,
}

local function tick(entities, dt, state)
    local new_entities = { hash = entities.hash }

    local player       = new_entities.hash.player

    for _, entity in ipairs(entities) do
        if entity.delete then
            if entity.id then
                new_entities.hash[entity.id] = nil
            end

            if player and player.interacting_with == entity then
                player.interacting_with = nil
            end
        else
            table.insert(new_entities, entity)
        end
    end

    for _, entity in ipairs(new_entities) do
        if entity.scale then
            entity.past_scale = entity.scale:copy()
        end

        if entity.rotation then
            entity.past_rotation = entity.rotation:copy()
        end

        if entity.position then
            entity.past_position = entity.position:copy()
        end

        -- PROCESS SEMI-SPATIAL MUSIC/AUDIO
        if entity.music then
            entity.music:setLooping(true)
            if entity.position then
                local volume = entity.music_volume or 1
                local area = entity.music_area or 8
                local dist = math.max(0, area - state.target:dist(entity.position)) / area
                entity.music:setVolume(dist * dist * volume)
            end

            if not entity.music:isPlaying() then
                entity.music:play()
            end
        end

        if entity.routine then
            local routine = scripts[entity.routine]
            if routine then
                table.insert(entity.scripts, coroutine.create(routine))
            end
            entity._routine = entity.routine
            entity.routine = nil
        end

        if entity.scripts then
            local i = #entity.scripts
            if i > 0 then
                local ok = coroutine.resume(entity.scripts[i], entity, dt, state)
                if not ok then
                    entity.scripts[i] = nil

                    if entity.interact_routine == i then
                        entity.in_interaction = false
                        player.interacting_with = nil
                    end
                end
            end
        end

        if entity.position then
            local dist = player.position:dist(entity.position)

            if player and entity.interact then
                local interaction = 0

                if (dist < (entity.distance or 2)) and not player.interacting_with then
                    interaction = 1

                    if input.just_pressed("action") then
                        assets.sfx_done:play()
                        player.interacting_with = entity
                        entity.routine = entity.interact
                        entity.interact_routine = #entity.scripts + 1
                    end
                end

                if entity.in_interaction then
                    interaction = 0
                end

                entity._interaction_anim = entity.interaction_anim or 0
                entity.interaction_anim = fam.decay(entity.interaction_anim or 0, interaction, 1, dt)
            end

            if entity.velocity then -- Euler integration
                -- TODO: FIX FORCE MATH!
                if entity.mass then
                    --entity.gravity = (entity.gravity or 0) + 10 * dt
                    --entity.velocity.y = entity.velocity.y - entity.gravity

                    -- entity.velocity.y = entity.velocity.y - dt * 32
                end

                if entity.collider then
                    local p                                  = entity.position + entity.collider.offset
                    local v                                  = entity.velocity * dt * 2

                    local new_position, new_velocity, planes =
                        state.hash:check(p, v, entity.collider.radius)

                    entity.velocity                          = new_velocity / dt

                    entity.collider.floor_time               = math.max(0, (entity.collider.floor_time or 0) - dt)
                    entity.collider.ceil_time                = math.max(0, (entity.collider.ceil_time or 0) - dt)
                    entity.collider.wall_time                = math.max(0, (entity.collider.wall_time or 0) - dt)

                    for _, plane in ipairs(planes) do
                        local i = plane.normal:dot(vector(0, -1, 0))

                        if math.abs(i) > 0.1 then
                            if i < 0 then
                                entity.collider.floor_time = coyote_time
                            else
                                entity.collider.ceil_time = coyote_time
                            end
                        else
                            entity.collider.wall_time = coyote_time
                        end
                    end

                    if entity.collider.floor_time == coyote_time then
                        entity.gravity = 0
                    end

                    entity.collider._past_position = entity.collider._position
                    entity.collider._position = new_position
                end

                entity.position = entity.position + entity.velocity * dt
                entity.velocity = entity.velocity:lerp(0, dt * 20)
            end

            -- This controls any element that has a "controller",
            -- like the player, the monsters, etc
            local control = controllers[entity.controller]
            if control then
                control(entity, dt, state)
            end
        end
    end

    return new_entities
end

local function render(entities, state, delta, alpha)
    if state.settings.debug then
        state:debug("")
        state:debug("--- ENTITIES -----")
        state:debug("ITEMS:  %i", #entities)
    end

    for _, entity in ipairs(entities) do
        if entity.position then
            local invisible = entity.invisible
            if not invisible then
                local pos, rot, scl = 0, 0, 1

                pos = (entity.past_position or entity.position):lerp(entity.position, alpha)

                if entity.rotation then
                    rot = (entity.past_rotation or entity.rotation):lerp(entity.rotation, alpha)
                end

                if entity.scale then
                    scl = (entity.past_scale or entity.scale):lerp(entity.scale, alpha)
                end

                if entity.camera_target then
                    state.target_true = pos:copy()
                end

                if entity.offset then
                    pos = pos - entity.offset
                end

                local call = {
                    color = entity.tint,
                    model = mat4.from_transform(pos, rot, scl),
                    mesh = entity.mesh
                }

                if entity.flip_x and entity.scale then
                    entity.scale.x = fam.decay(entity.scale.x, entity.flip_x, 3, delta)
                end

                if entity.sprite then
                    call.culling = "none"
                    call.translucent = 0.5

                    call.texture = entity.atlas or assets.tex_main
                    call.clip = {
                        entity.sprite[1] / call.texture:getWidth(),
                        entity.sprite[2] / call.texture:getHeight(),
                        entity.sprite[3] / call.texture:getWidth(),
                        entity.sprite[4] / call.texture:getHeight(),
                    }

                    call.mesh = assets.mod_quad
                end

                if call.mesh then
                    renderer.render(call)
                end

                if state.settings.debug and false then
                    local c = entity.collider
                    if c and c._position then
                        local _pos = (c._past_position or c._position):lerp(c._position, alpha)
                        renderer.render {
                            mesh = assets.mod_sphere,
                            model = mat4.from_transform(_pos, 0, c.radius),
                            color = { 1, 0, 1, 1 / 4 },
                            unshaded = true
                        }
                    end

                    local pos = pos - vector(0, 0.3, 0)

                    renderer.render {
                        culling = "none",
                        unshaded = true,
                        entity = entity,

                        model = mat4.from_transform(pos, 0, 3),

                        texture = function(call)
                            lg.setFont(assets.fnt_main)
                            local h = 64 - (assets.fnt_main:getHeight() / 2)

                            if call.entity.title then
                                local title = call.entity.title
                                local w = 64 - (assets.fnt_main:getWidth(title) / 2)
                                lg.print(title, w, h)
                            end
                            --lg.rectangle("fill", 0, 0, 2000, 2000)
                        end,

                        mesh = assets.mod_quad
                    }
                end

                if entity.interaction_anim then
                    local e = fam.lerp(entity._interaction_anim, entity.interaction_anim, alpha)
                    local pos = pos + vector(0, 0.1 + (e * e * 0.8), -0.05)
                    local a = e
                    if a > 0.99 then
                        a = 1
                    end

                    local rot = vector(0, 0, 0)
                    rot.z = math.sin(lt.getTime() * 3) * 0.2

                    renderer.render {
                        color = { 1, 1, 1, a * a },
                        model = mat4.from_transform(pos, rot, 1),
                        translucent = 0.5,
                        glow = 10,
                        mesh = assets.mod_bubble.mesh,
                        material = "general",
                    }
                end
            end
        end
    end
end

return {
    render = render,
    tick = tick,
    init = init
}
