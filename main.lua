local input = require "input"
local fam = require "fam"

local exm = require "lib.iqm"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local json = require "lib.json"

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
	settings.low_end = os.getenv("ABOVE_LOW_END")
	settings.debug = os.getenv("ABOVE_DEBUG")
	settings.fps = os.getenv("ABOVE_FPS") or settings.debug
	settings.linear = os.getenv("ABOVE_LINEAR") -- cursed mode
	settings.no_post = os.getenv("ABOVE_NO_POST") or settings.low_end
	settings.mute = os.getenv("ABOVE_MUTE")
	settings.fullscreen = os.getenv("ABOVE_FULLSCREEN") and true or false
	settings.scale = os.getenv("ABOVE_SCALE")
	settings.vsync = tonumber(os.getenv("ABOVE_VSYNC")) or 1
end
package.loaded.settings = settings

if not settings.linear then
	love.graphics.setDefaultFilter("nearest", "nearest")
end

love.window.setVSync(settings.vsync)
love.window.setFullscreen(settings.fullscreen)

-- GLOBALS!
local MAX_LIGHTS = 16
local COLOR_WHITE = {1, 1, 1, 1}
local CLIP_NONE = {0, 0, 1, 1}
_G.lg = love.graphics
_G.lm = love.math
_G.la = love.audio
_G.lt = love.timer

la.setVolume(tonumber(settings.mute) or 1)

local assets = require "assets"
local entities = require "entity"

local state = {
	render_list = {},
	entities = {},
	lights = {},

	scale = 2,
	zoom = 1,
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

-- This mechanism right here allows me to share uniforms in between
-- shaders AND automatically update them to reduce boilerplate.
local uniform_map = {}
local uniforms = {
	dither_table = {
		unpack = true,
		0.0625, 0.5625, 0.1875, 0.6875, 
		0.8125, 0.3125, 0.9375, 0.4375, 
		0.2500, 0.7500, 0.1250, 0.6250, 
		1.0000, 0.5000, 0.8750, 0.3750,
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
		table.insert(state.lights, {
			position = vector(light.position[1], light.position[3], -light.position[2]),
			color = {light.color[1], light.color[2], light.color[3], light.power }
		})
	end

	state.entities = {}
	for index, entity in ipairs(meta.objects) do
		entities.init(state.entities, entity, state)
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
		state.canvas_flat:release()
		
		state.canvas_main_a:release()
		state.canvas_depth_a:release()

		state.canvas_main_b:release()
		state.canvas_depth_b:release()
	end

	state.canvas_flat = lg.newCanvas(256, 256)

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
	if (k == "f11") then
		settings.fullscreen = not settings.fullscreen
		love.window.setFullscreen(settings.fullscreen)
	end
end

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
	end

	do 
		-- THE WATAH
		local pos = state.target:copy()
		pos.y = -1.5

		table.insert(state.render_list, {
			mesh = assets.water_mesh,
			color = fam.hex("#9d3be5"),
			model = mat4.from_transform(pos, 0, 40)
		})

		-- MAP STUFF
		for _, buffer in ipairs(state.map.meshes) do
			table.insert(state.render_list, {
				mesh = state.map.mesh,
				unshaded = buffer.material:match("unshaded"),
				range = {buffer.first, buffer.last - buffer.first}
			})
		end
	end

	entities.tick(state.entities, dt, state)

	state.target = state.target:decay(state.target_true, 1, dt)

	do -- Escape code
		if love.keyboard.isDown("escape") then
			state.escape = fam.decay(state.escape, 1, 0.5, dt)
		else
			state.escape = fam.decay(state.escape, 0, 3, dt)
		end

		if state.escape > 0.99 then
			love.event.quit()
		end
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
		'"guarded place."',
	}

	do -- Lighting code
		uniforms.ambient = {0.4, 0.4, 0.6, state.transition}
		--uniforms.ambient = {0.2, 0.2, 0.2, state.transition}
		uniforms.light_positions = { unpack = true }
		uniforms.light_colors = { unpack = true }
		uniforms.light_amount = #state.lights

		for _, light in ipairs(state.lights) do
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
		debug("CALLS:  %i", #state.render_list)
		debug("LIGHTS: %i/%i", #state.lights, MAX_LIGHTS)
	end

	-- Push the state, so now any changes will only happen locally
	lg.push("all")
		-- Set the current canvas
		lg.setCanvas({ state.canvas_main_a, depth = state.canvas_depth_a })
		--lg.clear({ 0x4f/255, 0x0a/255, 0xb0/255, 1 }, true, true)
		lg.clear(false, true, true)
		lg.setShader(assets.shader_gradient)
		assets.shader_gradient:send("bg_colora", fam.hex("#8438ff"))
		assets.shader_gradient:send("bg_colorb", fam.hex("#4f0ab0"))
		lg.draw(assets.white, 0, 0, 0, state.canvas_main_a:getWidth(), state.canvas_main_a:getHeight()*0.4)
		
		lg.setShader(assets.shader)
		
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
				mat4.from_transform(offset * 0.05 * 0.5, rot * 0.05 * 0.5, state.zoom)
		end

		local vertices = 0

		lg.setBlendMode("replace") -- NO BLENDING ALLOWED IN MY GAME.
		for index, call in ipairs(state.render_list) do
			lg.setColor(call.color or COLOR_WHITE)
			lg.setDepthMode(call.depth or "less", true)
			lg.setMeshCullMode(call.culling or "back")

			local light_amount = uniforms.light_amount
			local ambient = uniforms.ambient
			if call.unshaded then
				uniforms.light_amount = 0
				uniforms.ambient = COLOR_WHITE
			end

			uniforms.clip = call.clip or CLIP_NONE
			uniforms.model = call.model or mat4
			uniforms.translucent = call.translucent and 1 or 0

			if call.texture then
				call.mesh:setTexture(call.texture)
			end

			uniform_update(assets.shader)

			if call.range then
				call.mesh:setDrawRange(unpack(call.range))
			end

			lg.draw(call.mesh)

			uniforms.light_amount = light_amount
			uniforms.ambient = ambient

			call.mesh:setDrawRange()
			local v = call.range and call.range[2] or call.mesh:getVertexCount()
			vertices = vertices + v

			state.render_list[index] = nil
		end

		if settings.debug then
			debug("VERTS:  %i", vertices)
		end

		lg.setCanvas(state.canvas_main_a)

		lg.setShader()
		lg.setColor(COLOR_WHITE)
		lg.setBlendMode("alpha")
		lg.setFont(assets.font)
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