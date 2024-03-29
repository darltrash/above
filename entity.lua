local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local input = require "input"
local fam = require "fam"
local scripts = require "scripts"
local slam = require "lib.slam"
local log = require "lib.log"
local toml = require "lib.toml"

local assets = require "assets"
local renderer = require "renderer"
local permanence = require "permanence"

---------------------------------------------------------------

local coyote_time = 1 / 16

local data = love.filesystem.read("scripts/entities.toml")
local templates = toml.parse(data)


local initializers = {
    ["player"] = function(entity, state)
        log.info("i'll never forgive my aunt in finland for that can...")

        entity.controller = "player"
        entity.velocity = vector(0, 0, 0)
        entity.scale = vector(1, 1, 1)
        entity.rotation = vector(0, 0, 0)
        entity.camera_target = true

        entity.animation_power = 0
        state.target = entity.position:copy()

        entity.animation = 0
        entity.flip_x = 1
        entity.mesh = assets.mod_thenewdeer
        entity.collider = {
            offset = vector(0, 0, 0.7),
            radius = vector(0.3, 0.3, 0.73),

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
        entity.scale = vector(1, 1, 1)

        local template = templates[script]
        if template then
            for name, value in pairs(template) do
                entity[name] = value
            end
            entity.meshmap = assets["mod_"..entity.meshmap]
        end

        entity.id = "npc/"..script
    end
}

local function init(entities, raw, state)
    local title, numba = raw.name:match("(.+)%.(%d*)")
    title = title or raw.name

    local entity = {
        title = title,
        position = raw.position and vector.from_array(raw.position) or false
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
    { "front1", "front2", "front1", "front3" },
    { "back1", "back2", "back1", "back3" },
    { "side1", "side2" }
}

local controllers = {
    ["player"] = function(entity, dt, state)
        state.player = entity
        local dir = -input:get_direction()

        local velocity = vector(0, 0, 0)

        if state.settings.fps_camera then
            entity.tint[4] = 0
        end

        if not scripts.coroutine then
            dir = dir:rotate(state.camera_yaw, vector(0, 0, 1))

            velocity = vector(dir.x, -dir.y, 0) * 5

            local mag = velocity:magnitude()

            entity.rotation.z = fam.angle_lerp(entity.rotation.z, entity.rot or 0, dt * 16)
            if mag > 0 then
                entity.rot = -math.atan2(dir.y, dir.x)
                if entity.animation == 0 then
                    entity.animation = 1
                end
                entity.animation = entity.animation + dt * mag * 0.7
            else
                entity.animation = 0
            end

            if entity.collider.floor_time > 0 then
                if input.holding("jump") then
                    entity.velocity.z = 30
                end
            end
        end

        if not require("ui").done then
            entity.tint[4] = 0
        else
            entity.tint[4] = fam.lerp(entity.tint[4], 1, dt * 5) + (1 / 8)
        end

        local a = math.floor(entity.animation)

        local anim = PLAYER_ANIMS[entity.animation_index]
        entity.mesh_index = anim[(a % #anim) + 1]
        entity.velocity = entity.velocity + velocity

        --state.map_lights[1].position = entity.position + vector(0, 0, 2)
    end,
}

local function tick(entities, dt, state)
    local player = entities.hash.player

    for i=#entities, 1, -1 do
        local entity = entities[i]

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

        if entity.meshmap then
            if entity.past_mesh_index ~= entity.mesh_index then
                entity.past_mesh_index = entity.mesh_index
                
                entity.scale.z = 0.7
            end

            entity.scale.z = fam.lerp(entity.scale.z, 1, dt * 20)
        end

        if entity.position then
            local dist = player.position:dist(entity.position)

            if player and entity.interact then
                local interaction = 0

                if (dist < (entity.distance or 3)) and not scripts.coroutine then
                    interaction = 1

                    if input.just_pressed("action") then
                        assets.sfx_done:play()
                        scripts.spawn(entity.interact, nil, entity)
                    end
                end

                if entity.in_interaction then
                    interaction = 0
                end

                entity._interaction_anim = entity.interaction_anim or 0
                entity.interaction_anim = fam.decay(entity.interaction_anim or 0, interaction, 1, dt)
            end

            if entity.velocity then -- P H Y S I C S !
                -- TODO: FIX FORCE MATH!
                if not state.settings.no_physics then
--                    if entity.mass then
--                        entity.gravity = (entity.gravity or 0) + 10 * dt
--                        entity.velocity.z = entity.velocity.z - entity.gravity
--
--                        entity.velocity.z = entity.velocity.z - dt * 64
--                    end

                    if entity.collider then
                        local p = entity.position + entity.collider.offset
                        local v = entity.velocity * dt * 2

                        local function query(_, _, vel, pos)
                            local a = state.hash:intersectRay(pos, vel, false)
                            local triangles = {}
                            for _, v in ipairs(a) do
                                table.insert(triangles, v.triangle)
                            end

                            return triangles
                        end

                        local new_position, new_velocity, planes =
                            slam.check(p, v, entity.collider.radius, query)

                        entity.velocity = new_velocity / dt

                        entity.collider.floor_time = math.max(0, (entity.collider.floor_time or 0) - dt)
                        entity.collider.ceil_time  = math.max(0, (entity.collider.ceil_time  or 0) - dt)
                        entity.collider.wall_time  = math.max(0, (entity.collider.wall_time  or 0) - dt)

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
        
        if entity.delete then
            if player and player.interacting_with == entity then
                player.interacting_with = nil
            end

            entities[i] = entities[#entities]
            entities[#entities] = nil
            entities.hash[entity.id] = nil
        end
    end
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
                    state.target = pos:copy() + vector(0, 0, 1)
                end

                if entity.offset then
                    pos = pos - entity.offset
                end

                local call = {
                    color = entity.tint,
                    model = mat4.from_transform(pos, rot, scl),
                    mesh = entity.mesh,
                    culling = entity.culling,
                    material = "general"
                }

                if entity.flip_x and entity.scale then
                    entity.scale.x = fam.decay(entity.scale.x, entity.flip_x, 3, delta)
                end

                if entity.meshmap then
                    call.mesh = entity.meshmap
                    call.translucent = 1

                    for _, buffer in ipairs(entity.meshmap.meshes) do
                        if buffer.name == entity.mesh_index then
                            call.range = { buffer.first, buffer.last - buffer.first }
                            call.material = "general"
                            call.culling = "none"
                            break
                        end
                    end
                end

                if call.mesh then
                    renderer.render(call)
                end

                if state.settings.debug then
                    local c = entity.collider
                    if c and c._position then
                        local _pos = (c._past_position or c._position):lerp(c._position, alpha)
                        renderer.render {
                            mesh = assets.mod_sphere,
                            model = mat4.from_transform(_pos, 0, c.radius),
                            color = { 1, 0, 1, 1 / 4 },
                            material = "unshaded"
                        }
                    end

                    local pos = pos + vector(0, 0.1, 0)

                    renderer.render {
                        culling = "none",
                        unshaded = true,
                        translucent = 1,
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
                    local k = vector(0, -0.2, 0.4 + (e * e * 0.8))
                    k.w = 1
                    local pos = call.model:multiply_vec4(k)
                    local a = e
                    if a > 0.99 then
                        a = 1
                    end

                    local rot = vector(0, 0, 0)
                    rot.z = math.sin(lt.getTime() * 3) * 0.2

                    renderer.render {
                        color = { 1, 1, 1, a * a },
                        model = mat4.from_transform(pos, rot, 0.6),
                        translucent = 0.5,
                        glow = 0,
                        mesh = assets.mod_bubble.mesh,
                        material = "general",
                        culling = "none"
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
