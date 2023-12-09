local input = require "input"
local fam = require "fam"

local exm = require "lib.iqm"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local json = require "lib.json"
local log = require "lib.log"
local bvh = require "bvh"

local utf8 = require "utf8"

local lang = require "language"
lang.by_locale()

--jit.opt.start("-dce", 3)

local goodbye = fam.choice(lang.UI_GOODBYE)

-- SOME SETTINGS (sadly it uses env vars)
-- TODO: MOVE THIS TO "settings.lua"!
local settings = {}
do
	settings.low_end    = os.getenv("ABOVE_LOW_END")
	settings.debug      = os.getenv("ABOVE_DEBUG")
	settings.fps        = 1 or os.getenv("ABOVE_FPS") or settings.debug
	settings.linear     = os.getenv("ABOVE_LINEAR") -- cursed mode
	settings.volume     = os.getenv("ABOVE_VOLUME")
	settings.fullscreen = os.getenv("ABOVE_FULLSCREEN") and true or false
	settings.scale      = 1
	settings.vsync      = 0 or tonumber(os.getenv("ABOVE_VSYNC")) or 1
	settings.profile    = os.getenv("ABOVE_PROFILE")

	settings.disable_wobble = os.getenv("ABOVE_NO_WOBBLE")
	settings.ricanten 	= os.getenv("ABOVE_RICANTEN") -- ;)

	settings.level      = os.getenv("ABOVE_LEVEL") or nil
	settings.no_physics = settings.debug and os.getenv("ABOVE_NO_PHYSICS")

	settings.fps_camera = false
end

log.usecolor = not (love.system.getOS() == "Windows" or os.getenv("NO_COLOR"))

if not settings.linear then
	love.graphics.setDefaultFilter("nearest", "nearest")
end

love.window.setVSync(settings.vsync)
love.window.setFullscreen(settings.fullscreen)

-- GLOBALS!
_G.lg = love.graphics
_G.lm = love.math
_G.la = love.audio
_G.lt = love.timer
_G.lf = love.filesystem
_G.ls = love.system

la.setVolume(tonumber(settings.volume) or 1)

log.info("I love you! HAVE A GREAT TIME!")

local assets = require "assets"
local ui = require "ui"
local entities = require "entity"
local renderer = require "renderer"
local permanence = require "permanence"
--local _settings = require "settings"
local dialog = require "dialog"
local scripts = require "scripts"


local state = {
	entities = { hash = {} },
	new_entities = {},

	settings = settings,

	target = vector.zero:copy(),
	target_true = vector.zero:copy(),

	scale = 2,
	camera_pitch = -1.23,
	camera_yaw = 0,	
	camera_pos = vector.zero:copy(),

	escape = 0,
	transition = 1,

	transition_speed = 0,
	transition_callback = function()
		print("test test test")
	end,

	debug_lines = {},

	debug = function(self, str, ...)
		table.insert(self.debug_lines, str:format(...))
	end,

	render_target = {},

	daytime = 0.1,
	time_speed = 1,
}

-- (still somehow is) huge inspiration:
-- https://www.youtube.com/watch?v=6DRMC8-ZSIg&t=1066s

local grass = {}

local lovebird

if settings.debug then
	lovebird = require("lib.lovebird")
	lovebird.whitelist = nil
	lovebird.port = 1337
	lovebird.allowhtml = true
	lovebird.wrapprint = false

	_G.STATE = state
	
	log.info("Running on 0.0.0.0:%i", lovebird.port)
end

local triarea = function(v1, v2, v3)
	local edge1 = v2 - v1
	local edge2 = v3 - v1
	local crossProduct = edge1:cross(edge2)
	local area = crossProduct:magnitude() / 2
	return area
end

local grass_calls = {}

local rika

local function render_level()
	-- MAP STUFF
	local scripts = require "scripts"
	for _, buffer in ipairs(state.map.meshes) do
		local a = renderer.render {
			mesh = state.map.mesh,
			range = { buffer.first, buffer.last - buffer.first },
			material = buffer.material,
			box = buffer.box,
			texture = state.map_texture,
			roughness_map = state.map.roughness_map
		}
		
		local g = settings.ricanten and rika.materials[a.material]
		if g then
			a.texture = rika.materials[a.material].albedo
		end
	end

	-- THE WATAH
	local pos = state.target:copy()
	pos.z = 0

	renderer.render {
		mesh = assets.mod_water,
		model = mat4.from_transform(pos, 0, 1),
		order = math.huge,
		material = "water",
		no_shadow = true,
		no_reflection = true
	}

	for _, instance in ipairs(grass_calls) do
		renderer.render({
			material = "grass",
			mesh = assets.mod_grass,
			model = mat4.from_translation(instance)
		})
	end

	renderer.render {
		mesh = assets.mod_clouds,
		material = "clouds",
		model = mat4.from_transform(pos, { z = state.daytime * math.pi * 10 }, 5),
		color = { 1, 1, 1, 1 },
		no_shadow = true,
	}
end

function state.load_map(what)
	state.map_name = what
	if state.map_mesh then
		state.map_mesh:release()
		state.map_texture:release()
	end

	local file = ("assets/mod/%s.exm"):format(what)
	if settings.ricanten then
		file = "assets/rik/map.exm"
		rika = json.decode(lf.read("assets/rik/scene.json"))

		for _, material in pairs(rika.materials) do
			io.stdout:write(material.albedo, " ... ")
			if lf.getInfo("assets/rik/"..material.albedo) then
				print("✅")
				material.albedo = lg.newImage("assets/rik/"..material.albedo)
				material.albedo:setWrap("repeat", "repeat")
			else
				print("❌")
			end
		end
	end

	local map = exm.load(file, true)
	state.map = map
	local meta = json.decode(map.metadata)

	local function color_lerp(a, b, t)
		local a = fam.hex(a)
		local b = fam.hex(b)

		return {
			fam.lerp(a[1], b[1], t),
			fam.lerp(a[2], b[2], t),
			fam.lerp(a[3], b[3], t),
		}
	end

	local enable_grass = false

	local meshes = {}
	local last = {}
	state.triangles = {}
	local vertex_map = map.mesh:getVertexMap()
	for index, mesh in ipairs(map.meshes) do
		if enable_grass and mesh.material:match("grassful") then
			for i = mesh.first, mesh.last - 1, 3 do -- Triangles
				local v1 = vector(map.mesh:getVertexAttribute(vertex_map[i + 0], 1))
				local v2 = vector(map.mesh:getVertexAttribute(vertex_map[i + 1], 1))
				local v3 = vector(map.mesh:getVertexAttribute(vertex_map[i + 2], 1))

				local n = vector.normalize(vector.cross(v2 - v1, v3 - v1))
				local floor_dot = n:dot(vector(0, 1, 0))

				if floor_dot > 0.9 then
					local area = triarea(v1, v2, v3)

					for x = 1, math.floor(area * 3) do
						local a = love.math.random(0, 100) / 100
						local b = love.math.random(0, 100) / 100
						local p = v1:lerp(v2, a):lerp(v3, b)

						table.insert(grass_calls, p)
					end
				end
			end
			--mesh.material = "invisible.nocollide"
		end

		if not mesh.material:match("invisible") then
			if mesh.material == last.material
				and mesh.first == last.last then
				last.last = mesh.last

				for i = mesh.first, mesh.last - 1 do
					local v = vector(map.mesh:getVertexAttribute(vertex_map[i + 0], 1))
					last.box.min = last.box.min:min(v)
					last.box.max = last.box.max:max(v)
				end
			else
				-- OH MEIN GOTT MESHBOX REFERENCE
				mesh.box = {
					min = vector(0, 0, 0),
					max = vector(0, 0, 0)
				}

				for i = mesh.first, mesh.last - 1 do
					local v = vector(map.mesh:getVertexAttribute(vertex_map[i + 0], 1))
					mesh.box.min = mesh.box.min:min(v)
					mesh.box.max = mesh.box.max:max(v)
				end

				table.insert(meshes, mesh)
				last = mesh
				last.count = 0
			end
		end

		if not mesh.material:match("nocollide") then
			for i = mesh.first, mesh.last - 1, 3 do
				table.insert(state.triangles, {
					{ map.mesh:getVertexAttribute(vertex_map[i + 0], 1) },
					{ map.mesh:getVertexAttribute(vertex_map[i + 1], 1) },
					{ map.mesh:getVertexAttribute(vertex_map[i + 2], 1) }
				})
			end
		end
	end
	local origin = #map.meshes
	map.meshes = meshes
	log.info("Optimized level from %i meshes to %i, reduced to %i%%!", origin, #meshes, (#meshes / origin) * 100)
	log.info("Added %i/%i triangles to collision pool", #state.triangles, #map.triangles)

	state.hash = bvh.new(state.triangles)

	meta.lights = meta.lights or {}

	state.map_lights = {}
	for index, light in ipairs(meta.lights) do
		table.insert(state.map_lights, {
			position = vector(light.position[1], light.position[3], -light.position[2]),
			color = { light.color[1], light.color[2], light.color[3], light.power * 2 }
		})
	end

	state.entities = { hash = {} }
	for index, entity in ipairs(meta.objects) do
		entities.init(state.entities, entity, state)
	end

	if not state.entities.hash.player then
		entities.init(state.entities, {name = "player", position = {0, 0, 0}}, state)
	end

	--for index, collider in ipairs(meta.trigger_areas) do
	--	if collider.name:match("camera_box") then
	--		state.camera_box = {
	--			position = vector.from_array(transform(collider.position)),
	--			size = vector.from_array(transform(collider.size))
	--		}
	--	end
	--end

	local data = ("assets/tex/%s.png"):format(what)
	if love.filesystem.getInfo(data) then
		state.map.texture = lg.newImage(data)
		state.map.mesh:setTexture(state.map.texture)
		state.map.texture:setFilter("nearest", "nearest")
	end


	data = ("assets/tex/%s_roughness.png"):format(what)
	if love.filesystem.getInfo(data) then
		state.map.roughness_map = lg.newImage(data)
		state.map.roughness_map:setFilter("nearest", "nearest")
	end

	log.info(
		"Loaded map '%s': LIGHTS: %i, ENTITIES: %i",
		what, #state.map_lights, #state.entities
	)

	--render_level()
	--renderer.generate_ambient()
end

permanence.load(1)

state.load_map(settings.level or "wippa")

function love.load()
	if settings.profile then
		love.profiler = require('lib.profile')
		love.profiler.setclock(love.timer.getTime)
		love.profiler.start()
	end

	ui.load()

	scripts.env.state = state
	scripts.env.assets = assets

	if settings.debug and os.getenv("USER")~="darl" then
		scripts.spawn "000_helloworld"
	end
end

-- Handle window resize and essentially canvas (destruction and re)creation
function love.resize(w, h)
	-- Do some math and now we have a generalized scale for each pixel
	state.scale = tonumber(settings.scale) or math.max(1, math.floor(math.min(w, h) / 300))

	renderer.resize(w, h, state.scale)
end

function love.keypressed(k)
	if (k == "f11") then
		settings.fullscreen = not settings.fullscreen
		log.info("Fullscreen %s", settings.fullscreen and "enabled" or "disabled")
		love.window.setFullscreen(settings.fullscreen)
		love.resize(lg.getDimensions())
	elseif (k == "f3") then
		settings.fps_camera = not settings.fps_camera
		love.mouse.setRelativeMode(settings.fps_camera)
		love.mouse.setGrabbed(settings.fps_camera)
	end

	if settings.debug then
		if (k == "y") then
			state.daytime = state.daytime - (1 / 32)
		elseif (k == "u") then
			state.daytime = state.daytime + (1 / 32)
		end
	end
end

local timestep = 1 / 30
local lag = timestep

local current = 0
local max_deltas = 8
local deltas = {}
local t = 0
local frame = 1

function love.update(dt)
	current = current + 1
	frame = frame - 1

	deltas[current] = dt
	if current == max_deltas then
		current = 0
	end

	dt = 0
	for _, delta in ipairs(deltas) do
		dt = dt + delta
	end
	dt = dt / #deltas

	lag = lag + dt
	local n = 0
	while (lag > timestep) do
		input.update()
		local r = input.get_camera_movement() * 0.001
		state.camera_pitch = state.camera_pitch + r.y
		state.camera_yaw   = state.camera_yaw   - r.x

		lag = lag - timestep

		for index, entity in ipairs(state.new_entities) do
			entities.init(state.entities, entity, state)
			state.new_entities[index] = nil
		end

		scripts.env.entities = state.entities.hash
		scripts.update()
		entities.tick(state.entities, timestep, state)
		ui:on_tick(timestep)

		assets:update_anim9(timestep)

		n = n + 1
		if n == 5 then
			lag = 0
			log.info("CHOKING!")
			break
		end
	end

	t = t + dt
	if settings.profile and t > 5 then
		local report = love.profiler.report(20)
		love.profiler.reset()
		print(report)
		t = 0
	end

	-- Checks for updates in all configured input methods (Keyboard + Joystick)
	ui:update(dt)

	state.time = lt.getTime()

	-- Useful for shaders :)
	renderer.uniforms.time = state.time

	-- A day (including night) is equal to 5 minutes
	state.daytime = state.daytime + (state.time_speed * dt) / (10 * 60)
	state.daytime = state.daytime % 1
	renderer.uniforms.daytime = state.daytime

	if true then
		local eye
		do
			eye = state.target + vector(
				math.sin(state.camera_yaw),
				math.cos(state.camera_yaw),
				math.cos(state.camera_pitch)
			) * 5
		end
		state.camera_pos = state.camera_pos:lerp(eye, dt * 8)

		state.view_matrix = mat4.look_at(state.camera_pos, state.target, { z = 1 })

		local f = vector(1, 1, -1)
--		state.render_target.reflection = mat4.look_at(state.camera_pos * f, state.target, { z = 1 })

		local d = (state.daytime * 360)
		local position = vector(
			math.cos((d / 360) * math.pi * 2),
			0,
			math.sin((d / 360) * math.pi * 2)
		) * 10

		local off = vector(0, 0, 5)
		local true_sun = (position+off):normalize()
		renderer.uniforms.sun_direction = true_sun
		renderer.uniforms.sun = (position+off):normalize()
		local is_day = (state.daytime > 0 and state.daytime < 0.5) 
		state.render_target.sun = is_day and position:normalize() or false

		--if frame == 0 then
			renderer.generate_ambient(position:normalize())
		--	frame = 30
		--end

		renderer.uniforms.frame = (renderer.uniforms.frame or 0) + 1

		if not settings.disable_wobble then -- Cool camera movement effect
			local offset = vector(
				lm.noise(lt.getTime() * 0.1, lt.getTime() * 0.3),
				0,
				lm.noise(lt.getTime() * 0.2, lt.getTime() * 0.1)
			)

			state.view_matrix = state.view_matrix *
				mat4.from_transform(offset * 0.05, 0, 1)
		end

		if settings.debug then -- SUPER COOL FEATURE!
			lovebird.update()
		end

		render_level()
	end
	if settings.fps then
		state:debug("FPS:    %i", lt.getFPS())
	end

	if settings.debug then
		local w, h = lg.getDimensions()

		state:debug("MEMORY: %iKB",   collectgarbage("count"))
		state:debug("DELTA:  %ins",   dt * 1000000000)
		state:debug("TSTEP:  %ins",   timestep * 1000000000)
		state:debug("OS:     %s x%s", ls.getOS(), ls.getProcessorCount())
		state:debug("SCALE:  %i",     state.scale)
		state:debug("SIZE:   %ix%i",  lg.getDimensions())
		state:debug("INSIZE: %ix%i",  w/state.scale, h/state.scale)
		state:debug("CYCLE:  %f",     state.daytime)
		state:debug("SCRIPT: %s",     scripts.name)

		state:debug("")
		state:debug("CAMERA: X%im Y%im Z%im", state.target.x, state.target.y, state.target.z)
	end

	local alpha = fam.clamp(lag / timestep, 0, 1)
	entities.render(state.entities, state, dt, alpha)

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

log.info("Resolution is [%ix%i]", lg.getDimensions())

local function draw_text(font, text, x, y, scale)
	lg.push("all")
		lg.setShader(assets.shd_sdf_font)
		assets.shd_sdf_font:send("thicc", 0.8)

		lg.scale(scale)

		local tx = (x/scale)
		local ty = (y/scale) + font.characters["A"].height

		for c in text:gmatch(utf8.charpattern) do
			local nx = lt.getTime()*0.2
			local ny = (lt.getTime()+0.3)*0.3
			local n = love.math.noise((tx/10)+nx, (ty/10)+ny)
			local t = font.characters[c] or font.characters["?"]
		
			lg.draw(font.image, t.quad, tx-t.originX, ty-t.originY, (n-0.5)/14)
			tx = tx + t.advance
		end
	lg.pop()
end

local frame = 0
function love.draw()
	frame = frame + 1

	-- If the canvas hasnt been created yet
	local w, h = lg.getDimensions()
	if not state.resized then
		love.resize(w, h) -- Create one!
		state.resized = true
	end

	lg.reset()

	for _, light in ipairs(state.map_lights) do
		renderer.light(light)
	end

	if settings.debug then
		state:debug("MAP:    %s", state.map_name)
	end

	state.render_target.view = state.view_matrix
	state.render_target.shadow_view = state.shadow_view_matrix

	local target = renderer.draw(state.render_target, state)

	local r = function()
		lg.push("all")
		target.canvas_color:setFilter("nearest")
		lg.setShader(assets.shd_post)
		lg.scale(state.scale)
		assets.shd_post:send("light", target.canvas_light_pass)
		assets.shd_post:send("exposure", target.exposure)
		assets.shd_post:send("frame_index", frame)
		lg.draw(target.canvas_color)

		if settings.debug then
			local stats = lg.getStats()
			state:debug("")
			state:debug("--- LOVE.GRAPHICS ---")
			state:debug("CALLS: %i", stats.drawcalls)
			state:debug("IMGS:  %i", stats.images)
			--state:debug("IMGS:  %i", stats.texturememory)
		end

		ui:draw(w / state.scale, h / state.scale, state)

		lg.setShader()
		lg.setBlendMode("alpha")
		lg.setFont(assets.fnt_main)
		for i, v in ipairs(state.debug_lines) do
			lg.print(v, 4, 16 * (i - 1), 0, 2)

			state.debug_lines[i] = nil
		end

		lg.scale(1/state.scale)
		lg.scale(state.scale+1)
		local k = fam.hex"#18002e"
		lg.setColor(k[1], k[2], k[3], state.escape * state.escape)
		lg.rectangle("line", (w / (state.scale * 2)) - 120, 2, w, 20)
		lg.setColor(k[1], k[2], k[3], 1)
		lg.rectangle("fill", (w / (state.scale * 2)) - 120, 2, w, 20 * (state.escape * state.escape))
		lg.setColor(1, 1, 1, state.escape * state.escape)
		draw_text(assets.fnt_atkinson, goodbye, (w / (state.scale * 2)) - 115, 4, 1/4)
		lg.pop()
	end

	r()
end

-- i love you,
--
