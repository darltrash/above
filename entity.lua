local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local input = require "input"
local fam = require "fam"
local scripts = require "scripts"

local assets = require "assets"
local renderer = require "renderer"

---------------------------------------------------------------

local initializers = {
    ["player"] = function (entity, state)
        entity.controller = "player"
        entity.velocity = vector()
        entity.scale = vector()
        entity.rotation = vector()
        entity.camera_target = true

        entity.animation_power = 0
        state.target = entity.position:copy()

        entity.collider = {
            x=-0.4, y=0, z=0,
            w=0.8, h=0.8, d=0.1
        }
    end,

    ["npc"] = function (entity, state, script)
        entity.sprite = {0, 224, 32, 32}
        entity.routine = script
    end
}

local function init(entities, raw, state)
    local title = raw.name:match("(.+)%.%d+")

    local entity = {
        title = title,
        -- Change Z=1 to Y=1
        position = vector(raw.position[1], raw.position[3], -raw.position[2])
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

    table.insert(entities, entity)
end

--------------------------------------------------------------

local SPR_PLAYER_LEFT_RIGHT = {0, 0, 32, 32}

local controllers = {
    ["player"] = function (entity, dt, state)
        state.player = entity
        local dir = -input:get_direction()

        entity.velocity = vector(dir.x, 0, dir.y) * 2.5
        entity.flip_x = entity.flip_x or 1

        local dirs = dir:sign()
        if dirs.x ~= 0 then
            entity.flip_x = -dirs.x
        end

        entity.scale.x = fam.decay(entity.scale.x, entity.flip_x, 3, dt)
        
        local anim = 0
        if dir:magnitude() > 0 then
            anim = 1

            local a = math.abs(math.sin(lt.getTime() * 15))
            if a > 0.8 or a < 0.2 then
                assets.step_sound:setVolume(lm.random(20, 70)/100)
                assets.step_sound:play()
            end
        end

        entity.animation_power = fam.decay(entity.animation_power or 0, anim, 3, dt)
        entity.rotation.z = math.sin(lt.getTime() * 15) * 0.1 * entity.animation_power
        entity.scale.y = 1 - (math.abs(math.sin(lt.getTime() * 15)) * entity.animation_power * 0.1)
    
        entity.sprite = SPR_PLAYER_LEFT_RIGHT
    end,
}

local function tick(entities, dt, state)
    if state.settings.debug then
        state:debug("")
        state:debug("--- ENTITIES -----")
        state:debug("ITEMS:  %i", #entities)
    end

	for _, entity in ipairs(entities) do
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
                entity.script = coroutine.create(routine)
            end
            entity._routine = entity.routine
            entity.routine = nil
        end

        if entity.script then
            local ok = coroutine.resume(entity.script, entity, dt, state)
            if not ok then
                coroutine.script = nil
            end
        end

		if entity.position then
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
                local call = {
                    color = entity.tint,
                    model = mat4.from_transform(
                        entity.position, entity.rotation or 0, entity.scale or 1),
                    mesh = entity.mesh
                }

                if entity.sprite then
                    call.culling = "none"
                    call.translucent = true

                    call.texture = entity.atlas or assets.atlas
                    call.clip = {
                        entity.sprite[1] / call.texture:getWidth(),
                        entity.sprite[2] / call.texture:getHeight(),
                        entity.sprite[3] / call.texture:getWidth(),
                        entity.sprite[4] / call.texture:getHeight(),
                    }
                    
                    call.mesh = assets.quad_model
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
                            lg.setFont(assets.font)
                            if call.title then
                                local w = 64 - (assets.font:getWidth(call.title)/2)
                                local h = 64 - (assets.font:getHeight()/2)
                                lg.print(call.title, w, h)
                            end
                            --lg.rectangle("fill", 0, 0, 2000, 2000)
                        end,

                        mesh = assets.quad_model
                    }
                end
            end
        end
	end
end

return {
    tick = tick,
    init = init
}