local input = require "input"
local fam = require "fam"

local exm = require "lib.iqm"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local json = require "lib.json"
local log = require "lib.log"

local lang = require "language"
lang.by_locale()

-- // TODO: GET RID OF THIS HIDEOUS BEAST.
local moonshine = require "lib.moonshine"
local effect = moonshine(moonshine.effects.scanlines)
	.chain(moonshine.effects.chromasep)
	.chain(moonshine.effects.crt)

effect.crt.feather = 0.005
effect.crt.distortionFactor = { 1.03, 1.03 }
effect.scanlines.opacity = 0.1

-- SOME SETTINGS (sadly it uses env vars)
local settings = {}
do
	settings.low_end = os.getenv("ABOVE_LOW_END")
	settings.debug   = os.getenv("ABOVE_DEBUG")
	settings.fps     = os.getenv("ABOVE_FPS") or settings.debug
	settings.linear  = os.getenv("ABOVE_LINEAR") -- cursed mode
	settings.no_post = os.getenv("ABOVE_NO_POST") or settings.low_end
	settings.volume  = os.getenv("ABOVE_VOLUME")
	settings.fullscreen = os.getenv("ABOVE_FULLSCREEN") and true or false
	settings.scale   = os.getenv("ABOVE_SCALE")
	settings.vsync   = tonumber(os.getenv("ABOVE_VSYNC")) or 1

	settings.level = os.getenv("ABOVE_LEVEL") or nil

	settings.fps_camera = false
end

log.usecolor = not (love.system.getOS()=="Windows" or os.getenv("no_color"))

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

local assets = require "assets"
local ui = require "ui"
local entities = require "entity"
local renderer = require "renderer"
local permanence = require "permanence"
--local _settings = require "settings"

local state = {
	entities = { hash = {} },
	new_entities = {},

	settings = settings,

	target = vector.zero:copy(),
	target_true = vector.zero:copy(),

	scale = 2,
	zoom = 1,
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

	daytime = 0,

	hash = require("hash").new()
}

local camera_rotation = vector(0, 0, 0)
local grass = {}

local lovebird

if settings.debug then
	lovebird = require("lib.lovebird")
	lovebird.whitelist = nil
	lovebird.port = 1337

	_G.STATE = state

	log.info("Running on 0.0.0.0:%i", lovebird.port)
end

local triarea = function (v1, v2, v3)
	local edge1 = v2 - v1
    local edge2 = v3 - v1
    local crossProduct = edge1:cross(edge2)
    local area = crossProduct:magnitude() / 2
    return area
end

local grass_meshes = {}

local function render_level()
	-- MAP STUFF
	for _, buffer in ipairs(state.map.meshes) do
		renderer.render {
			mesh = state.map.mesh,
			range = { buffer.first, buffer.last - buffer.first },
			material = buffer.material,
			box = buffer.box,
			texture = state.map_texture
		}
	end

	-- THE WATAH
	local pos = state.target:copy()
	pos.y = -1.5
	
	--renderer.render {
	--	mesh = assets.mod_water,
	--	color = fam.hex("#a46cff"),
	--	model = mat4.from_transform(pos, 0, 60),
	--	order = math.huge,
	--	--material = "water"
	--}

	for _, instance in ipairs(grass_meshes) do
		instance.material = "grass"
		renderer.render(instance)
	end

	renderer.render {
		mesh = assets.mod_clouds,
		material = "clouds",
		model = mat4.from_transform(0, { y = state.daytime * math.pi }, 10),
		color = {1, 1, 1, 1/4},
	}
end

function state.load_map(what)
	state.map_name = what
	if state.map_mesh then
		state.map_mesh:release()
		state.map_texture:release()
	end

	local map = exm.load(("assets/mod/%s.exm"):format(what), true)
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

	local meshes = {}
	local last = {}
	state.triangles = {}
	local vertex_map = map.mesh:getVertexMap()
	for index, mesh in ipairs(map.meshes) do
		if mesh.material:match("grassful") then
			for i=mesh.first, mesh.last-1, 3 do -- Triangles
				local v1 = vector(map.mesh:getVertexAttribute(vertex_map[i+0], 1))
				local v2 = vector(map.mesh:getVertexAttribute(vertex_map[i+1], 1))
				local v3 = vector(map.mesh:getVertexAttribute(vertex_map[i+2], 1))

				local n = vector.normalize(vector.cross(v2 - v1, v3 - v1))
				local floor_dot = n:dot(vector(0, 1, 0))

				if floor_dot > 0.9 then
					local grass_mesh = {
						box = {
							min = vector(),
							max = vector()
						}
					}
					local triangles = {}

					local function process(a)
						grass_mesh.box.min = grass_mesh.box.min:min(a)
						grass_mesh.box.max = grass_mesh.box.max:max(a)
	
						return a
					end

					local c1 = map.mesh:getVertexAttribute(vertex_map[i+0], 5)
					local c2 = map.mesh:getVertexAttribute(vertex_map[i+1], 5)
					local c3 = map.mesh:getVertexAttribute(vertex_map[i+2], 5)

					local area = triarea(v1, v2, v3)

					for x=1, math.floor(area*50) do
						local a = love.math.random(0, 100)/100
						local b = love.math.random(0, 100)/100
						local p = v1:lerp(v2, a):lerp(v3, b)
						local c = fam.lerp(fam.lerp(c1, c2, a), c3, b)

						local k = p * 0.25
						local i = 0.4 + (love.math.noise(k.x, k.y, k.z) * 0.5) * c

						local r = lm.random(-1, 1)

						local v1 = process(p - vector(0.2, 0, 0):rotate(r, vector(0, 1, 0))*(0.2+c))
						local v2 = process(p + vector(0.2, 0, 0):rotate(r, vector(0, 1, 0))*(0.2+c))
						local v3 = process(p + vector(0, 1, 0) * i)

						local top = color_lerp("#ff5100", "#db5800", i)
						local bot = fam.hex("#bd0000", 1)

						table.insert(triangles, { v1.x, v1.y, v1.z,  0, 0, 1,  bot[1], bot[2], bot[3], 1 })
						table.insert(triangles, { v3.x, v3.y, v3.z,  0, 0, 1,  top[1], top[2], top[3], 1 })
						table.insert(triangles, { v2.x, v2.y, v2.z,  0, 0, 1,  bot[1], bot[2], bot[3], 1 })
					end

					if #triangles > 10 then
						grass_mesh.mesh = lg.newMesh(
							{
								{"VertexPosition", "float", 3},
								{"VertexNormal", "float", 3},
								{"VertexColor", "float", 4},
							}, triangles, "triangles"
						)

						table.insert(grass_meshes, grass_mesh)
					end
				end
			end
			mesh.material = "invisible.nocollide"
		end

		if not mesh.material:match("invisible") then
			if mesh.material == last.material
				and mesh.first == last.last then
				last.last = mesh.last

				for i=mesh.first, mesh.last-1 do
					local v = vector(map.mesh:getVertexAttribute(vertex_map[i+0], 1))
					last.box.min = last.box.min:min(v)
					last.box.max = last.box.max:max(v)
				end

			else
				mesh.box = {
					min = vector(0, 0, 0),
					max = vector(0, 0, 0)
				}

				for i=mesh.first, mesh.last-1 do
					local v = vector(map.mesh:getVertexAttribute(vertex_map[i+0], 1))
					mesh.box.min = mesh.box.min:min(v)
					mesh.box.max = mesh.box.max:max(v)
				end

				table.insert(meshes, mesh)
				last = mesh

			end
		end

		if not mesh.material:match("nocollide") then
			for i=mesh.first, mesh.last-1, 3 do
				table.insert(state.triangles, {
					{map.mesh:getVertexAttribute(vertex_map[i+0], 1)},
					{map.mesh:getVertexAttribute(vertex_map[i+1], 1)},
					{map.mesh:getVertexAttribute(vertex_map[i+2], 1)}
				})
			end
		end
	end
	local origin = #map.meshes
	map.meshes = meshes
	log.info("Optimized level from %i meshes to %i, reduced to %i%%!", origin, #meshes, (#meshes/origin)*100)
	log.info("Added %i/%i triangles to collision pool", #state.triangles, #map.triangles)

	state.hash:add_triangles(state.triangles, "level")

	state.map_lights = {}
	for index, light in ipairs(meta.lights) do
		table.insert(state.map_lights, {
			position = vector(light.position[1], light.position[3], -light.position[2]),
			color = { light.color[1], light.color[2], light.color[3], light.power }
		})
	end

	state.entities = { hash = {} }
	for index, entity in ipairs(meta.objects) do
		entities.init(state.entities, entity, state)
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

	log.info(
		"Loaded map '%s': LIGHTS: %i, ENTITIES: %i",
		what, #state.map_lights, #state.entities
	)

	render_level()
	--renderer.generate_ambient()
end

permanence.load(1)

state.load_map(settings.level or "untitled")

-- Handle window resize and essentially canvas (destruction and re)creation
function love.resize(w, h)
	-- Do some math and now we have a generalized scale for each pixel
	state.scale = tonumber(settings.scale) or math.max(1, math.floor(math.min(w, h) / 300))

	renderer.resize(w, h, state.scale)

	effect.resize(w, h)
	effect.scanlines.frequency = h / state.scale
	effect.chromasep.radius = state.scale / 2
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
end

function love.mousemoved(x, y, dx, dy)
	camera_rotation.x = camera_rotation.x + dx * 0.001
	camera_rotation.y = camera_rotation.y + dy * 0.001
end

local timestep = 1/30
local lag = timestep

local current = 0
local max_deltas = 8
local deltas = {}

function love.update(dt)
	current = current + 1

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

		lag = lag - timestep

		for index, entity in ipairs(state.new_entities) do
			entities.init(state.entities, entity, state)
			state.new_entities[index] = nil
		end

		state.entities = entities.tick(state.entities, timestep, state)
		ui:on_tick(timestep)
		
		n = n + 1
		if n == 5 then
			lag = 0
			log.info("CHOKING!")
			break
		end
	end

	-- Checks for updates in all configured input methods (Keyboard + Joystick)
	ui:update(dt)

	state.time = lt.getTime()

	-- Useful for shaders :)
	renderer.uniforms.time = state.time

	state.daytime = state.time * 0.01
	renderer.uniforms.daytime = state.daytime

	renderer.generate_ambient()

	if true then
		local eye
		do
			eye = (vector(0, 1.5, -6) * state.zoom) + state.target

			if state.camera_box then
				local p = state.camera_box.position
				local s = state.camera_box.size:round() - 2 -- margin

				eye.x = fam.clamp(eye.x, p.x - s.x, p.x + s.x)
				eye.z = fam.clamp(eye.z, p.z + s.z, p.z - s.z)
			end
		end

		state.view_matrix = mat4.look_at(eye, state.target+vector(0, 0.5, 0), { y = 1 })

		state.shadow_view_matrix = mat4.look_at(eye, state.target+vector(0, 0.5, 0), { y = 1 })

		if settings.fps_camera then
			local pos = state.target + vector(0, 1, 0)

			local rot = vector(
				math.cos(camera_rotation.x),
				-math.sin(camera_rotation.y),
				math.sin(camera_rotation.x)
			)

			state.view_matrix = mat4.look_at(pos, pos+rot, { y = 1 })
		end
		
		renderer.uniforms.frame = (renderer.uniforms.frame or 0) + 1

		do -- Cool camera movement effect
			local offset = vector(
				lm.noise(lt.getTime() * 0.1, lt.getTime() * 0.3),
				lm.noise(lt.getTime() * 0.2, lt.getTime() * 0.1),
				0
			)

			local rot = vector(
				0, 0,
				lm.noise(lt.getTime() * 0.12, lt.getTime() * 0.1) - 0.5
			)

			state.view_matrix = state.view_matrix *
				mat4.from_transform(offset * 0.05 * 0.5, rot * 0.05 * 0.5, 1)
		end

		if settings.debug then -- SUPER COOL FEATURE!
			lovebird.update()
		end

		render_level()
	end

	--state.view_matrix = mat4.look_at(0, {x = 1}, {y = 1})

	if settings.fps_camera and settings.debug then
		state:debug("FPS CAMERA IS ON!")
		state:debug("")
	end

	if settings.fps then
		state:debug("FPS:    %i", lt.getFPS())
	end

	if settings.debug then
		state:debug("MEMORY: %iKB", collectgarbage("count"))
		state:debug("DELTA:  %ins", dt * 1000000000)
		state:debug("TSTEP:  %ins", timestep * 1000000000)
		state:debug("OS:     %s x%s", ls.getOS(), ls.getProcessorCount())
		state:debug("SCALE:  %i", state.scale)
		state:debug("SIZE:   %ix%i", lg.getDimensions())
	end

	local alpha = fam.clamp(lag / timestep, 0, 1)
	entities.render(state.entities, state, dt, alpha)

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

log.info("Resolution is [%ix%i]", lg.getDimensions())

function love.draw()
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

	local target = renderer.draw(state.render_target, state)

	local r = function()
		lg.push("all")
			assets.shd_post:send("color_a", fam.hex"#00093b")
			assets.shd_post:send("color_b", fam.hex"#ff0080")
			assets.shd_post:send("power",  0.2)
			target.canvas_color:setFilter("nearest")
			lg.setShader(assets.shd_post) -- TODO: Move to multi-pass blur!
			lg.scale(state.scale)
			assets.shd_post:send("light", target.canvas_light_pass)
			assets.shd_post:send("resolution", {target.canvas_light_pass:getDimensions()})
			assets.shd_post:send("exposure", target.exposure)
			lg.draw(target.canvas_color)

			lg.setShader()
			lg.setBlendMode("alpha")
			lg.setFont(assets.fnt_main)
			for i, v in ipairs(state.debug_lines) do
				lg.print(v, 4, 8 * (i - 1))

				state.debug_lines[i] = nil
			end

			ui:draw(w/state.scale, h/state.scale)

			lg.scale(2)
			lg.setColor(0, 0, 0, state.escape * state.escape)
			lg.rectangle("line", (w / (state.scale * 2)) - 73, 2, w, 12)
			lg.setColor(0, 0, 0, 1)
			lg.rectangle("fill", (w / (state.scale * 2)) - 73, 2, w, 12 * (state.escape * state.escape))
			lg.setColor(1, 1, 1, state.escape * state.escape)
			lg.print("OYASUMI!", (w / (state.scale * 2)) - 70)
		lg.pop()
	end

	if settings.no_post then
		r()
	else
		effect(r)
	end
end

-- i love you,
--             
