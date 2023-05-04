local exm = require "lib.iqm"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local input = require "input"
local json = require "lib.json"
local fam = require "fam"

local noop = function () end

-- // TODO: GET RID OF THIS HIDEOUS BEAST. 
local moonshine = require "lib.moonshine"
local effect = moonshine(moonshine.effects.scanlines)
				.chain(moonshine.effects.chromasep)
				.chain(moonshine.effects.crt)

effect.crt.feather = 0.005
effect.crt.distortionFactor = {1.03, 1.03}
effect.scanlines.opacity = 0.1

-- SOME SETTINGS (sadly it uses env vars)
local settings = {}
do
	settings.debug = os.getenv("ABOVE_DEBUG")
	settings.fps = os.getenv("ABOVE_FPS") or settings.debug
	settings.linear = os.getenv("ABOVE_LINEAR") -- cursed mode
	settings.no_post = os.getenv("ABOVE_NO_POST")
	settings.mute = os.getenv("ABOVE_MUTE")
	settings.fullscreen = os.getenv("ABOVE_FULLSCREEN") and true or false
	settings.scale = os.getenv("ABOVE_SCALE")

end

if not settings.linear then
	love.graphics.setDefaultFilter("nearest", "nearest")
end

love.window.setFullscreen(settings.fullscreen)

-- GLOBALS!
local COLOR_WHITE = {1, 1, 1, 1}
local CLIP_NONE = {0, 0, 1, 1}
_G.lg = love.graphics
_G.lm = love.math
_G.la = love.audio
_G.lt = love.timer

--local music = love.audio.newSource("assets/mus_brothermidi.mp3", "static")
--music:setLooping(true)
--music:play()

la.setVolume(tonumber(settings.mute) or 1)

local water_mesh = exm.load("assets/mod_water.exm").mesh
local step_sound = la.newSource("assets/snd_step.ogg", "static")

local state = {
	scale = 2,
	target = vector.zero:copy(),
	target_true = vector.zero:copy(),
	canvas_switcheroo = false,
	escape = 0,
	transition = 1,
	transition_speed = 0,
	transition_callback = function ()
		print("test test test")
	end
}

local shader = lg.newShader "assets/shd_basic.glsl"
local font = lg.newFont("assets/fnt_monogram.ttf", 16)
local atlas = lg.newImage("assets/atl_main.png")
local quad_model = exm.load("assets/mod_quad.exm").mesh
quad_model:setTexture(atlas)

-- This mechanism right here allows me to share uniforms in between
-- shaders AND automatically update them to reduce boilerplate.
local uniform_map = {}
local uniforms = {
	dither_table = {
		unpack = true,
		0.0625, 0.5625, 0.1875, 0.6875, 0.8125, 0.3125, 0.9375,
		0.4375, 0.25, 0.75, 0.125, 0.625, 1.0, 0.5, 0.875, 0.375,
	}
}

local function uniform_update(shader)
	uniform_map[shader] = uniform_map[shader] or {}
	local map = uniform_map[shader]

	for k, v in pairs(uniforms) do
		if map[k] ~= v and shader:hasUniform(k) then
			if mat4.is_mat4(v) then
				shader:send(k, "column", v:to_columns())
			elseif type(v) == "table" and v.unpack then
				shader:send(k, unpack(v))
			else
				shader:send(k, v)
			end
		end
		map[k] = v
	end
end

local lights = {}
local entities = {
	{
		sprite = {0, 0, 32, 32},
		position = vector(0, 0, 0),
		rotation = vector(0, 0, 0),
		velocity = vector(0, 0, 0),
		camera_target = true,
		controller = "player"
	},

	{
		position = vector(0, 0, 0),
		music = la.newSource("assets/mus_small_town.mp3", "stream"),
		music_volume = 0
	}
}

local map_name = ""
local function load_map(what)
	map_name = what
	if state.map_mesh then
		state.map_mesh:release()
		state.map_texture:release()
	end

	local map = exm.load(("assets/%s.exm"):format(what))
	state.map = map
	local meta = json.decode(map.metadata)

	for index, light in ipairs(meta.lights) do
		table.insert(lights, {
			position = vector(light.position[1], light.position[3], -light.position[2]),
			color = {light.color[1], light.color[2], light.color[3], light.power * 0.2}
		})
	end

	state.map.texture = lg.newImage(("assets/%s.png"):format(what))
	state.map.mesh:setTexture(state.map.texture)
end

load_map("mod_lighthouse")

-- Handle window resize and essentially canvas (destruction and re)creation
function love.resize(w, h)
	-- Do some math and now we have a generalized scale for each pixel
	state.scale = tonumber(settings.scale) or math.max(1, math.floor(math.min(w, h)/300))

	-- If the canvases already exist, YEET THEM OUT (safely).
	if state.canvas_main_a then
		state.canvas_main_a:release()
		state.canvas_depth_a:release()

		state.canvas_main_b:release()
		state.canvas_depth_b:release()
	end

    state.canvas_main_a  = lg.newCanvas(w/state.scale, h/state.scale, { format = "rgba8" })
    state.canvas_depth_a = lg.newCanvas(w/state.scale, h/state.scale, { format = "depth16", readable = true, msaa=1 })

	-- // TODO: DO GRAB PASS STUFF ////////
	state.canvas_main_b  = lg.newCanvas(w/state.scale, h/state.scale, { format = "rgba8" })
    state.canvas_depth_b = lg.newCanvas(w/state.scale, h/state.scale, { format = "depth16", readable = true, msaa=1 })

	effect.resize(w, h)
	effect.scanlines.frequency = h / state.scale
	effect.chromasep.radius = state.scale
end

local debug_lines = {} -- Debug stuff!

function love.keypressed(k)
	if (k == "f3") then
		load_map("mod_lighthouse")
	elseif (k == "f11") then
		settings.fullscreen = not settings.fullscreen
		love.window.setFullscreen(settings.fullscreen)
	elseif (k == "f6") then
		state.transition_speed = -1
	end
end

local render_list = {}
function love.update(dt)
	-- Checks for updates in all configured input methods (Keyboard + Joystick)
	input:update()

	-- Useful for shaders :)
	uniforms.time = (uniforms.time or 0) + dt

	if settings.debug then -- SUPER COOL FEATURE!
		local lovebird = require("lib.lovebird")
		lovebird.whitelist = nil
		lovebird.port = 1337
		lovebird.update()
		_G.STATE = state
	end

	do 
		-- THE WATAH
		local pos = state.target:copy()
		pos.y = -1.5

		table.insert(render_list, {
			mesh = water_mesh,
			color = {0x9d/255, 0x3b/255, 0xe5/255, 1},
			model = mat4.from_transform(pos, 0, 20)
		})

		-- MAP STUFF
		for _, buffer in ipairs(state.map.meshes) do
			table.insert(render_list, {
				mesh = state.map.mesh,
				unshaded = buffer.material:match("unshaded"),
				range = {buffer.first, buffer.last - buffer.first}
			})
		end
	end

	-- Process entities
	for _, entity in ipairs(entities) do
		if entity.music then
			entity.music:setLooping(true)
			if entity.position then
				local volume = entity.music_volume or 1
				local area = entity.music_area or 8
				local dist = math.max(0, area-state.target:dist(entity.position))/area
				entity.music:setVolume(dist * dist* volume)
			end
			
			if not entity.music:isPlaying() then
				entity.music:play()
			end
		end

		if not entity.position then -- If it doesnt even have a position
			goto continue -- Then why even bother?
		end

		-- This controls any element that is considered a "player"
		if entity.controller == "player" then
			local dir = -input:get_direction()

			entity.velocity = vector(dir.x, 0, dir.y) * 2.5
			entity.scale = entity.scale or vector(1, 1, 1)
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
					step_sound:setVolume(lm.random(20, 70)/100)
					step_sound:play()
				end

			end
			entity.animation_power = fam.decay(entity.animation_power or 0, anim, 3, dt)

			entity.rotation.z = math.sin(lt.getTime() * 15) * 0.1 * entity.animation_power
			entity.scale.y = 1 - (math.abs(math.sin(lt.getTime() * 15)) * entity.animation_power * 0.1)
			
			entity.camera_target = true
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
				call.translucent = 1
				call.clip = {
					entity.sprite[1] / atlas:getWidth(),
					entity.sprite[2] / atlas:getHeight(),
					entity.sprite[3] / atlas:getWidth(),
					entity.sprite[4] / atlas:getHeight(),
				}
				
				call.mesh = quad_model
			end
		
			if call.mesh then
				table.insert(render_list, call)
			end
		end

		:: continue ::
	end

	state.target = state.target:decay(state.target_true, 1, dt)

	if love.keyboard.isDown("escape") then
		state.escape = fam.decay(state.escape, 1, 0.5, dt)
	else
		state.escape = fam.decay(state.escape, 0, 3, dt)
	end

	if state.escape > 0.99 then
		love.event.quit()
	end

	do -- Transition code
		state.transition = state.transition + state.transition_speed * 2 * dt
		if state.transition <= 0 then
			state.transition = 0
			state.transition_speed = -state.transition_speed
		end

		if state.transition > 1 then
			state.transition = 1
			state.transition_speed = 0
			state.transition_callback()
		end
	end
end

function love.draw()
	-- If the canvas hasnt been created yet
	local w, h = lg.getDimensions()
	if not state.canvas_main_a then
		love.resize(w, h) -- Create one!
	end

	debug_lines = {
		"/////////////////////////////",
		"/ ABOVE, 0.01, DEMO MODE ON /",
		"/////////////////////////////",
		"",

		"PRESS F3 TO MOVE ON.",
		"PRESS F11 FOR FULLSCREEN.",
		"MAP:    " .. map_name:upper(),
		""
	}

	do -- Lighting code
		uniforms.ambient = {0.5, 0.5, 0.7, state.transition}
		--uniforms.ambient = {0.2, 0.2, 0.2, state.transition}
		uniforms.light_positions = { unpack = true }
		uniforms.light_colors = { unpack = true }
		uniforms.light_amount = #lights

		for _, light in ipairs(lights) do
			local pos = light.position:to_array()
			pos.w = 1
			table.insert(uniforms.light_positions, pos)
			table.insert(uniforms.light_colors, light.color)
		end

		if uniforms.light_amount == 0 then
			uniforms.light_positions = nil
			uniforms.light_colors = nil
		end
	end

	local function debug(str, ...)
		table.insert(debug_lines, str:format(...))
	end

	if settings.fps then
		debug("FPS:    %i", lt.getFPS())
	end

	if settings.debug then
		debug("DELTA:  %ins", lt.getAverageDelta() * 1000000000)
		debug("TARGET: %s", state.target_true:round())
		debug("CALLS:  %i", #render_list)
		debug("LIGHTS: %i", #lights)
	end

	-- Push the state, so now any changes will only happen locally
	lg.push("all")
		-- Set the current canvas
		lg.setCanvas({ state.canvas_main_a, depth = state.canvas_depth_a })
		lg.clear({ 0x4f/255, 0x0a/255, 0xb0/255, 1 }, true, true)
		lg.setShader(shader)
		
		uniforms.projection = mat4.from_perspective(-45, -w/h, 0.01, 1000)
		uniforms.model = mat4.from_transform(0, 0, 0)
		uniforms.view = mat4.look_at(vector(0, 2, -6) + state.target, state.target, { y = 1 })

		do -- Cool camera movement effect
			local offset = vector(
				lm.noise( lt.getTime()*0.1, lt.getTime()*0.3 ),
				lm.noise( lt.getTime()*0.2, lt.getTime()*0.1 ),
				0
			)

			local rot = vector(
				0, 0,
				lm.noise( lt.getTime()*0.12, lt.getTime()*0.1 ) - 0.5
			)

			uniforms.view = uniforms.view *
				mat4.from_transform(offset * 0.05 * 0.5, rot * 0.05 * 0.5, 1)
		end

		local vertices = 0

		lg.setBlendMode("replace") -- NO BLENDING ALLOWED IN MY GAME.
		for index, call in ipairs(render_list) do
			lg.setColor(call.color or COLOR_WHITE)
			lg.setDepthMode(call.depth or "less", true)
			lg.setMeshCullMode(call.culling or "back")

			uniforms.translucent = call.translucent and 1 or 0
			
			local light_amount = uniforms.light_amount
			local ambient = uniforms.ambient
			if call.unshaded then
				uniforms.light_amount = 0
				uniforms.ambient = COLOR_WHITE
			end

			uniforms.clip = call.clip or CLIP_NONE
			uniforms.model = call.model or mat4

			uniform_update(shader)

			if call.range then
				call.mesh:setDrawRange(unpack(call.range))
			end

			lg.draw(call.mesh)

			uniforms.light_amount = light_amount
			uniforms.ambient = ambient

			if call.range then
				call.mesh:setDrawRange()
				vertices = vertices + call.range[2]
			else
				vertices = vertices + call.mesh:getVertexCount()
			end

			render_list[index] = nil
		end

		if settings.debug then
			debug("VERTS:  %i", vertices)
		end

		lg.setCanvas(state.canvas_main_a)

		lg.setShader()
		lg.setColor(COLOR_WHITE)
		lg.setBlendMode("alpha")
		lg.setFont(font)
		for i, v in ipairs(debug_lines) do
			lg.print(v, 4, 8*(i-1))
		end

		lg.scale(2)
		lg.setColor(0, 0, 0, state.escape*state.escape)
		lg.rectangle("line", (w/(state.scale*2)) - 73, 2, w, 12)
		lg.setColor(0, 0, 0, 1)
		lg.rectangle("fill", (w/(state.scale*2)) - 73, 2, w, 12*(state.escape*state.escape))
		lg.setColor(1, 1, 1, state.escape*state.escape)
		lg.print("QUITTER...", (w/(state.scale*2)) - 70)
	lg.pop()

	if settings.no_post then
		lg.draw(state.canvas_main_a, 0, 0, 0, state.scale)
	else
		effect(lg.draw, state.canvas_main_a, 0, 0, 0, state.scale)
	end
	
end