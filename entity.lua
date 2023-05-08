local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local input = require "input"
local fam = require "fam"

local assets = require "assets"

---------------------------------------------------------------

local initializers = {
    ["player"] = function (entity, state)
        entity.controller = "player"
        entity.velocity = vector()
        entity.scale = vector()
        entity.rotation = vector()
        entity.camera_target = true
        entity.sprite = {0, 0, 32, 32}

        entity.animation_power = 0
        state.target = entity.position:copy()
    end
}

local function init(entities, raw, state)
    local entity = {
        
        -- Change Z=1 to Y=1
        position = vector(raw.position[1], raw.position[3], -raw.position[2])
    }

    local init = initializers[raw.name:match("(.+)%.%d+")]
    if init then
        init(entity, state)
    end

    table.insert(entities, entity)
end

--------------------------------------------------------------

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
    end,
}

local function tick(entities, dt, state)
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

		if entity.position then
            -- This controls any element that has a "controller",
            -- like the player, the monsters, etc
            local control = controllers[entity.controller]
            if control then
                control(entity, dt, state)
            end

            -- // TODO: Implement fixed timesteps
            if entity.velocity then -- Euler integration
                entity.position = entity.position + entity.velocity * dt
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
                    table.insert(state.render_list, call)
                end
            end
        end
	end
end

return {
    tick = tick,
    init = init
}