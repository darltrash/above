local input = require "input"
local fam = require "fam"

local exm = require "lib.iqm"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local json = require "lib.json"
local log = require "lib.log"

local bump = require "lib.bump"

local noop = function () end

log.usecolor = love.system.getOS ~= "Windows"

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
	settings.volume = os.getenv("ABOVE_VOLUME")
	settings.fullscreen = os.getenv("ABOVE_FULLSCREEN") and true or false
	settings.scale = os.getenv("ABOVE_SCALE")
	settings.vsync = tonumber(os.getenv("ABOVE_VSYNC")) or 1

	settings.level = settings.debug and os.getenv("ABOVE_LEVEL") or nil
end

if not settings.linear then
	love.graphics.setDefaultFilter("nearest", "nearest")
end

love.window.setVSync(settings.vsync)
love.window.setFullscreen(settings.fullscreen)

-- GLOBALS!
local MAX_LIGHTS = 16
local COLOR_WHITE = {1, 1, 1, 1}
local COLOR_BLACK = {0, 0, 0, 1}
local CLIP_NONE = {0, 0, 1, 1}
_G.lg = love.graphics
_G.lm = love.math
_G.la = love.audio
_G.lt = love.timer

la.setVolume(tonumber(settings.volume) or 1)

local assets = require "assets"
local entities = require "entity"

local state = {
	render_list = {},
	grab_render_list = {},
	entities = {},
	lights = {},

	settings = settings,

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
	},

	harmonics = {
		unpack = true,
		{ 0.7953949,  0.4405923,  0.5459412},
		{ 0.3981450,  0.3526911,  0.6097158},
		{-0.3424573, -0.1838151, -0.2715583},
		{-0.2944621, -0.0560606,  0.0095193},
		{-0.1123051, -0.0513088, -0.1232869},
		{-0.2645007, -0.2257996, -0.4785847},
		{-0.1569444, -0.0954703, -0.1485053},
		{ 0.5646247,  0.2161586,  0.1402643},
		{ 0.2137442, -0.0547578, -0.3061700}
	}
}

function state.render(call)
	if not call.order then
		call.order = 0
		if call.model then
			local position = call.model:multiply_vec4({0, 0, 0, 1})
			call.order = state.eye:dist(position)
		end
	end

	if call.shader then
		return table.insert(state.grab_render_list, call)
	end
	table.insert(state.render_list, call)
end

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

	state.colliders = bump.newWorld()

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

	for index, collider in ipairs(meta.trigger_areas) do
		local scale = vector(collider.size[1], collider.size[3], collider.size[2])*2
		local position = vector(-collider.position[1], collider.position[3], -collider.position[2]) - (scale/2)

		state.colliders:add (
			collider,
			position.x, position.y, position.z,
			scale.x, scale.y, scale.z
		)
	end

	local data = ("assets/%s.png"):format(what)
	if love.filesystem.getInfo(data) then
		state.map.texture = lg.newImage(data)
		state.map.mesh:setTexture(state.map.texture)
	end

	log.info(
		"Loaded map '%s',\n>\tLIGHTS: %i, ENTITIES: %i, COLLS: %i",
		what, #state.lights, #state.entities, #meta.trigger_areas
	)
end

load_map(settings.level or "mod_lighthouse")

local avg_values = {}

-- Handle window resize and essentially canvas (destruction and re)creation
function love.resize(w, h)
	-- Do some math and now we have a generalized scale for each pixel
	state.scale = tonumber(settings.scale) or math.max(1, math.floor(math.min(w, h)/300))

	-- If the canvases already exist, YEET THEM OUT (safely).
	if state.canvas_main_a then
		state.canvas_flat:release()
		
		state.canvas_normals_a:release()
		state.canvas_main_a:release()
		state.canvas_depth_a:release()

		state.canvas_normals_b:release()
		state.canvas_main_b:release()
		state.canvas_depth_b:release()
	end

	state.canvas_flat = lg.newCanvas(128, 128)

	local function canvas(t)
		local f = t.filter
		t.filter = nil

		local w = math.floor(math.ceil(w/state.scale) * 2) / 2
		local h = math.floor(math.ceil(h/state.scale) * 2) / 2
		local c = lg.newCanvas(w, h, t)
		if f then
			c:setFilter(f, f)
		end

		return c
	end

	-- ////////////// A CANVAS /////////////

	state.canvas_main_a  = canvas {
		format = "rg11b10f",
		mipmaps = "auto"
	}
    state.canvas_normals_a = canvas {
		format = "rgb10a2",
		mipmaps = "auto",
		filter = "nearest"
	}
    state.canvas_depth_a = canvas {
		format = "depth24",
		mipmaps = "manual",
		readable = true,
		filter = "linear"
	}

	-- ////////////// B CANVAS /////////////

	state.canvas_main_b  = canvas {
		format = "rg11b10f",
		mipmaps = "auto"
	}
    state.canvas_normals_b = canvas {
		format = "rgb10a2",
		mipmaps = "auto",
		filter = "nearest"
	}
    state.canvas_depth_b = canvas {
		format = "depth24",
		mipmaps = "manual",
		readable = true,
		filter = "linear"
	}

	effect.resize(w, h)
	effect.scanlines.frequency = h / state.scale
	effect.chromasep.radius = state.scale
end

local debug_lines = {} -- Debug stuff!

function love.keypressed(k)
	if (k == "f11") then
		settings.fullscreen = not settings.fullscreen
		log.info("Fullscreen %s", settings.fullscreen and "enabled" or "disabled")
		love.window.setFullscreen(settings.fullscreen)
		love.resize(lg.getDimensions())
	elseif (k == "f3") then
		local avg = 0
		for k, v in ipairs(avg_values) do
			avg = avg + v
		end
		log.info("sexo: %i", avg / #avg_values)
	end
end

function love.update(dt)
	-- Checks for updates in all configured input methods (Keyboard + Joystick)
	input:update()

	-- Useful for shaders :)
	uniforms.time = (uniforms.time or 0) + dt
	uniforms.view = mat4.look_at(vector(0, 2, -6) + state.target, state.target, { y = 1 })
	uniforms.frame = (uniforms.frame or 0) + 1

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

	state.eye = vector.from_table(uniforms.view:multiply_vec4 {0, 0, 0, 1})

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

		-- MAP STUFF
		for _, buffer in ipairs(state.map.meshes) do
			state.render {
				mesh = state.map.mesh,
				unshaded = buffer.material:match("unshaded"),
				range = {buffer.first, buffer.last - buffer.first},
			}
		end

		state.render {
			mesh = assets.water_mesh,
			color = fam.hex("#9d3be5"),
			model = mat4.from_transform(pos, 0, 60),
			order = math.huge,
			shader = assets.shader_water,
		}
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
		debug("EYE:    %s", state.eye:round())
		debug("CALLS:  %i", #state.render_list)
		debug("LIGHTS: %i/%i", #state.lights, MAX_LIGHTS)

		for k, v in ipairs(state.colliders:getItems()) do
			local x, y, z, w, h, d = state.colliders:getCube(v)
			local scale = vector(w, h, d)
			local position = vector(x, y, z) + (scale / 2)
			state.render {
				mesh = assets.cube,
				model = mat4.from_transform(position, 0, scale),
				color = {1, 0, 1, 1/4},
				unshaded = true
			}
		end
	end

	local cswitch = false
	local canvas_color = state.canvas_main_a
	local canvas_depth = state.canvas_depth_a
	local canvas_normal = state.canvas_normals_a

	local function switch_canvas()
		lg.push("all")
			uniforms.back_normal = canvas_normal
			uniforms.back_color  = canvas_color
			uniforms.back_depth  = canvas_depth

			cswitch = not cswitch

			canvas_normal = cswitch 
				and state.canvas_normals_b or state.canvas_normals_a
				
			canvas_color  = cswitch 
				and state.canvas_main_b or state.canvas_main_a
				
			canvas_depth  = cswitch 
				and state.canvas_depth_b or state.canvas_depth_a

			lg.setCanvas({ canvas_color, canvas_normal, depthstencil = canvas_depth })
			lg.clear(true, true, true)
			lg.setColor(COLOR_WHITE)

			lg.setShader(assets.shader_copy)
			assets.shader_copy:send("color", uniforms.back_color)
			assets.shader_copy:send("normal", uniforms.back_normal)
			lg.setDepthMode("always", true)
			lg.draw(uniforms.back_depth)
		lg.pop()
	end

	-- Push the state, so now any changes will only happen locally
	lg.push("all")	
		lg.setCanvas({canvas_color, canvas_normal, depthstencil=canvas_depth})
		lg.clear(true, true, true)

		lg.setBlendMode("replace") -- NO BLENDING ALLOWED IN MY GAME.

		lg.setShader(assets.shader_gradient)
		assets.shader_gradient:send("bg_colora", fam.hex("#a166ff"))
		assets.shader_gradient:send("bg_colorb", fam.hex("#eb8a44"))
		lg.draw(assets.white, 0, 0, 0, state.canvas_main_a:getWidth(), state.canvas_main_a:getHeight()*0.4)

		lg.setShader(assets.shader)
		
		uniforms.projection = mat4.from_perspective(-45, -w/h, 0.01, 1000)
		uniforms.model = mat4.from_transform(0, 0, 0)
		uniforms.inverse_proj = uniforms.projection:inverse()

		local vertices = 0

		local function render(call)
			local color = call.color or COLOR_WHITE

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
				if type(call.texture) == "function" then
					lg.push("all")
						lg.reset()
						lg.setCanvas(state.canvas_flat)
						lg.clear(0, 0, 0, 0)
						lg.setColor(1, 1, 1, 1)
						call:texture()
					lg.pop()

					call.mesh:setTexture(state.canvas_flat)

				else
					call.mesh:setTexture(call.texture)

				end
			end

			local v = call.mesh:getVertexCount()
			if call.range then
				call.mesh:setDrawRange(unpack(call.range))
				v = call.range[2]
			end

			local shader = assets.shader
			if call.shader then
				shader = call.shader
				switch_canvas()
			end

			lg.setCanvas({canvas_color, canvas_normal, depthstencil = canvas_depth})
			lg.setDepthMode(call.depth or "less", true)
			lg.setMeshCullMode(call.culling or "back")

			lg.setColor(color)
			
			uniform_update(shader)
			lg.setShader(shader)

			lg.draw(call.mesh)

			call.mesh:setDrawRange()

			uniforms.light_amount = light_amount
			uniforms.ambient = ambient

			vertices = vertices + v
		end

		local time = love.timer.getTime()

		table.sort(state.render_list, function(a, b)
			return a.order > b.order
		end)
		for index, call in ipairs(state.render_list) do
			render(call)
			state.render_list[index] = nil
		end

		table.sort(state.grab_render_list, function(a, b)
			return a.order < b.order
		end)
		for index, call in ipairs(state.grab_render_list) do
			render(call)
			state.grab_render_list[index] = nil
		end

		if settings.debug then
			--table.insert(avg_values, (love.timer.getTime() - time) * 1000000000)
			debug("RENDER: %ins", (love.timer.getTime() - time) * 1000000000)
			debug("VERTS:  %i", vertices)
		end

		lg.setCanvas(canvas_color)

		lg.setShader()
		lg.setColor(COLOR_BLACK)
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

	lg.reset()

	switch_canvas()

	lg.push("all")
		lg.setShader(assets.shader_depth_copy)
		lg.setDepthMode("always", true)

		for x=1, canvas_depth:getMipmapCount() do
			lg.setCanvas({depthstencil = {canvas_depth, mipmap = x}})

			lg.draw(uniforms.back_depth, 0, 0, 0, 1/x)
		end
	lg.pop()

	local r = function ()
		lg.push("all")
		lg.setColor(1, 1, 1, 1)
		lg.clear(1, 1, 1, 1)

		lg.setBlendMode("multiply", "premultiplied")
		lg.setShader(assets.shader_post)
		lg.draw(canvas_color, 0, 0, 0, state.scale)

		if not settings.not_ssao then
			lg.setShader(assets.shader_gtao)

			assets.shader_gtao:send("depth_texture", canvas_depth)
			assets.shader_gtao:send("normal_texture", canvas_normal)
			assets.shader_gtao:send("inverse_proj", "column", uniforms.inverse_proj:to_columns())
			assets.shader_gtao:send("frame", 1)

			lg.draw(canvas_color, 0, 0, 0, state.scale)
		end
		lg.pop()
	end

	if settings.no_post then
		r()
	else
		effect(r)
	end
	
end