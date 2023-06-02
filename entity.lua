local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local input = require "input"
local fam = require "fam"
local scripts = require "scripts"

local assets = require "assets"
local renderer = require "renderer"
local permanence = require "permanence"

---------------------------------------------------------------

local initializers = {
    ["player"] = function (entity, state)
        entity.controller = "player"
        entity.velocity = vector(0, 0, 0)
        entity.scale = vector(0, 0, 0)
        entity.rotation = vector(0, 0, 0)
        entity.camera_target = true

        entity.animation_power = 0
        state.target = entity.position:copy()

        entity.animation = 0
        entity.flip_x = 1
        entity.atlas = assets.tex_deer_person
        entity.collider = {
            x=-0.2, y=0, z=0,
            w=0.4, h=0.8, d=0.1
        }

        entity.tint = {1, 1, 1, 1}

        entity.id = "player"
        entity.offset = vector(0, 0, 0)
        entity.animation_index = 1
    end,

    ["npc"] = function (entity, state, script)
        entity.sprite = {0, 224, 32, 32}
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

    if entity.position and entity.collider then
        local x = entity.position.x - entity.collider.x
        local y = entity.position.y - entity.collider.y
        local z = entity.position.z - entity.collider.z

        local w = entity.collider.w
        local h = entity.collider.h
        local d = entity.collider.d
        state.colliders:add(entity, x, y, z, w, h, d)
    end

    if entity.id then
        entities.hash[entity.id] = entity
    end

    table.insert(entities, entity)
end

--------------------------------------------------------------

local PLAYER_ANIMS = {
    {
        {   0,   0, 112, 112, off = 0 },
        { 112,   0, 112, 112, off = 1 },
        {   0,   0, 112, 112, off = 0 },
        { 224,   0, 112, 112, off = 1 },
    },

    {
        {   0, 112, 112, 112, off = 0 },
        { 112, 112, 112, 112, off = 1 },
        {   0, 112, 112, 112, off = 0 },
        { 224, 112, 112, 112, off = 1 },
    },

    {
        {   0, 224, 112, 112, off = 0 },
        { 112, 224, 112, 112, off = 1 },
    }
}

local controllers = {
    ["player"] = function (entity, dt, state)
        state.player = entity
        local dir = -input:get_direction()

        entity.velocity = vector(0, 0, 0)

        if (not entity.interacting_with) and require("ui").done then
            entity.velocity = vector(dir.x, 0, dir.y) * 3.5
        end

        if not require("ui").done then
            entity.tint[4] = 0
        else
            entity.tint[4] = fam.lerp(entity.tint[4], 1, dt*2)
        end

        local anim = 0
        local mag = entity.velocity:magnitude()
        if mag > 0 then
            anim = 1

            local a = math.abs(math.sin(lt.getTime() * 15))
            if a > 0.8 or a < 0.2 then
                assets.sfx_step:setVolume(lm.random(20, 70)/100)
                assets.sfx_step:play()
            end

            if entity.animation == 0 then
                entity.animation = 1
            end
            entity.animation = entity.animation + dt * mag * 1.4
        else
            entity.animation = 0
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

        local anim = PLAYER_ANIMS[entity.animation_index]
        entity.sprite = anim[(math.floor(entity.animation)%#anim)+1]
        entity.scale.y = 1
        entity.offset.y = fam.lerp(entity.offset.y, -entity.sprite.off*0.14, dt*25)
    end,
}

local function tick(entities, dt, state)
    if state.settings.debug then
        state:debug("")
        state:debug("--- ENTITIES -----")
        state:debug("ITEMS:  %i", #entities)
    end

    local new_entities  = { hash = entities.hash }

    local player = new_entities.hash.player

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
        -- PROCESS SEMI-SPATIAL MUSIC/AUDIO 
		if entity.music then
			entity.music:setLooping(true)
			if entity.position then
				local volume = entity.music_volume or 1
				local area = entity.music_area or 8
				local dist = math.max(0, area-state.target:dist(entity.position))/area
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
                        entity.interact_routine = #entity.scripts+1
                    end
                end

                if entity.in_interaction then
                    interaction = 0
                end

                entity.interaction_anim = fam.decay(entity.interaction_anim or 0, interaction, 1, dt)
            end    

            -- This controls any element that has a "controller",
            -- like the player, the monsters, etc
            local control = controllers[entity.controller]
            if control then
                control(entity, dt, state)
            end

            -- // TODO: Implement fixed timesteps
            if entity.velocity then -- Euler integration
                local position = entity.position + entity.velocity * dt

                if state.colliders:hasItem(entity) then
                    local x, y, z = state.colliders:move(
                        entity,
                        position.x+entity.collider.x,
                        position.y+entity.collider.y,
                        position.z+entity.collider.z
                    )

                    position.x = x - entity.collider.x
                    position.y = y - entity.collider.y
                    position.z = z - entity.collider.z
                end

                entity.position = position
            end

            if entity.camera_target then
                state.target_true = entity.position
            end

            local invisible = entity.invisible
            if not invisible then
                local pos = entity.position:copy()
                if entity.offset then
                    pos = pos - entity.offset
                end
                
                local call = {
                    color = entity.tint,
                    model = mat4.from_transform(
                        pos, entity.rotation or 0, entity.scale or 1),
                    mesh = entity.mesh
                }

                if entity.flip_x and entity.scale then
                    entity.scale.x = fam.decay(entity.scale.x, entity.flip_x, 3, dt)
                end

                if entity.sprite then
                    call.culling = "none"
                    call.translucent = true

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

                if state.settings.debug then
                    local pos = entity.position-vector(0, 0.3, 0)

                    renderer.render {
                        culling = "none",
                        translucent = true,
                        unshaded = true,
                        title = entity.title,
                        
                        model = mat4.from_transform(pos, 0, 3),

                        texture = function (call)
                            lg.setFont(assets.fnt_main)
                            if call.title then
                                local w = 64 - (assets.fnt_main:getWidth(call.title)/2)
                                local h = 64 - (assets.fnt_main:getHeight()/2)
                                lg.print(call.title, w, h)
                            end
                            --lg.rectangle("fill", 0, 0, 2000, 2000)
                        end,

                        mesh = assets.mod_quad
                    }
                end

                if entity.interaction_anim then
                    local e = entity.interaction_anim
                    local pos = entity.position+vector(0, 0.1+(e*e*0.8), 0)
                    local a = e
                    if a > 0.99 then
                        a = 1
                    end

                    renderer.render {
                        color = {1, 1, 1, a*a},
                        model = mat4.from_transform(pos, math.sin(lt.getTime()*3)*0.2, 0.5),
                        translucent = true,
                        texture = assets.tex_ui,
                        clip = {
                            0, 0,
                            64 / assets.tex_ui:getWidth(),
                            64 / assets.tex_ui:getHeight()
                        },
                        mesh = assets.mod_quad
                    }
                end
            end
        end
	end

    return new_entities
end

return {
    tick = tick,
    init = init
}