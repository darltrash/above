local input = require "input"
local fam = require "fam"

local exm = require "lib.iqm"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local json = require "lib.json"
local log = require "lib.log"

local bump = require "lib.bump"
local fysx = require "fysx"

local world = fysx.new()

local noop = function()
end

log.usecolor = love.system.getOS ~= "Windows"

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
	settings.debug = os.getenv("ABOVE_DEBUG")
	settings.fps = os.getenv("ABOVE_FPS") or settings.debug
	settings.linear = os.getenv("ABOVE_LINEAR") -- cursed mode
	settings.no_post = os.getenv("ABOVE_NO_POST") or settings.low_end
	settings.volume = os.getenv("ABOVE_VOLUME")
	settings.fullscreen = os.getenv("ABOVE_FULLSCREEN") and true or false
	settings.scale = os.getenv("ABOVE_SCALE")
	settings.vsync = tonumber(os.getenv("ABOVE_VSYNC")) or 1

	settings.level = settings.debug and os.getenv("ABOVE_LEVEL") or nil

	settings.fps_camera = false
end

if not settings.linear then
	love.graphics.setDefaultFilter("nearest", "nearest")
end

love.window.setVSync(settings.vsync)
love.window.setFullscreen(settings.fullscreen)

-- GLOBALS!
local MAX_LIGHTS = 16
_G.lg = love.graphics
_G.lm = love.math
_G.la = love.audio
_G.lt = love.timer
_G.lf = love.filesystem

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
	end
}

local camera_rotation = vector(0, 0, 0)

local sphere = vector(1, 4, 0)
local sphere_vel = vector(0, 0, 0)
local gravity = 0

local map_name = ""
local function load_map(what)
	map_name = what
	if state.map_mesh then
		state.map_mesh:release()
		state.map_texture:release()
	end

	state.colliders = bump.newWorld()

	local map = exm.load(("assets/mod/%s.exm"):format(what), true)
	state.map = map
	local meta = json.decode(map.metadata)

	local meshes = {}
	local last = {}
	for index, mesh in ipairs(map.meshes) do -- Re-Batch stuff.
		if mesh.material == last.material
			and mesh.first == last.last then
			last.last = mesh.last
		else
			table.insert(meshes, mesh)
			last = mesh
		end
	end
	map.meshes = meshes

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

	local function transform(a)
		return { a[1], a[3], -a[2] }
	end

	for index, collider in ipairs(meta.trigger_areas) do
		if collider.name:match("camera_box") then
			state.camera_box = {
				position = vector.from_array(transform(collider.position)),
				size = vector.from_array(transform(collider.size))
			}
		end

--		local position = vector.from_array(collider.position)
--		local scale = vector.from_array(collider.size)
--
--		state.colliders:add(
--			collider,
--			position.x, position.z, -position.y,
--			scale.x, scale.z, scale.y
--		)
	end

	local data = ("assets/%s.png"):format(what)
	if love.filesystem.getInfo(data) then
		state.map.texture = lg.newImage(data)
		state.map.mesh:setTexture(state.map.texture)
	end

	local triangles = {}
	for _, triangle in ipairs(map.triangles) do
		table.insert(triangles, {
			transform(triangle[1].position),
			transform(triangle[2].position),
			transform(triangle[3].position)
		})
	end
	world:add_triangles(triangles, "level")

	log.info(
		"Loaded map '%s',\n>\tLIGHTS: %i, ENTITIES: %i, COLLS: %i",
		what, #state.map_lights, #state.entities, #meta.trigger_areas
	)
end

permanence.load(1)

load_map(settings.level or "forest")

local avg_values = {}

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
	elseif (k == "f3") then -- DO NOT USE THIS
		settings.fps_camera = not settings.fps_camera
		love.mouse.setGrabbed(settings.fps_camera)
		love.mouse.setRelativeMode(settings.fps_camera)
	end
end

function love.mousemoved(x, y, dx, dy)
end

function love.update(dt)
	-- Checks for updates in all configured input methods (Keyboard + Joystick)
	input:update()
	ui:update(dt)

	state.time = lt.getTime()

	-- Useful for shaders :)
	renderer.uniforms.time = (renderer.uniforms.time or 0) + dt

	local eye
	do
		eye = vector(0, 2, -6) + state.target

		if state.camera_box then
			local p = state.camera_box.position
			local s = state.camera_box.size:round() - 2 -- margin

			eye.x = fam.clamp(eye.x, p.x - s.x, p.x + s.x)
			eye.z = fam.clamp(eye.z, p.z + s.z, p.z - s.z)
		end
	end

	state.eye = eye --vector.lerp(state.eye or eye, eye, dt * 4)

	renderer.uniforms.view = mat4.look_at(state.eye, state.target+vector(0, 0.5, 0), { y = 1 })

	if settings.fps_camera then
		renderer.uniforms.view = mat4.look_at(state.target, state.target+camera_rotation, { y = 1 })
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

		renderer.uniforms.view = renderer.uniforms.view *
			mat4.from_transform(offset * 0.05 * 0.5, rot * 0.05 * 0.5, state.zoom)
	end

	state.eye = vector.from_table(renderer.uniforms.view:multiply_vec4 { 0, 0, 0, 1 })

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
			renderer.render {
				mesh = state.map.mesh,
				range = { buffer.first, buffer.last - buffer.first },
				material = buffer.material,
			}
		end

		renderer.render {
			mesh = assets.mod_water,
			color = fam.hex("#a46cff"),
			model = mat4.from_transform(pos, 0, 60),
			order = math.huge,
			material = "water"
		}

		if input.just_pressed("action") then
			sphere = state.entities.hash.player.position + vector(0, 4, 0)
			sphere_vel = vector(0, 0, 0)

		end

		if settings.debug and state.camera_box then
			renderer.render {
				mesh = assets.mod_cube,
				color = fam.hex("#823be5", 1/4),
				model = mat4.from_transform(state.camera_box.position, 0, state.camera_box.size*2),
			}
		end

		--gravity = gravity + dt

		--[[
		local velocity = sphere_vel + vector(0, -gravity, 0)
		local next, penetration, normal = world:check(sphere, velocity * dt, 0.5)
		sphere = next

		if normal then
			normal = vector.from_table(normal)
			
			if normal:dot(vector(0, 1, 0)) > 0.9 then
				gravity = 0
			end

			sphere_vel = sphere_vel + normal * penetration * 5
		end

		renderer.render {
			mesh = assets.sphere,
			unshaded = true,
			color = fam.hex("#ff0095"),
			model = mat4.from_transform(sphere, lt.getTime(), 0.5)
		}
		]]
	end

	if settings.fps_camera and settings.debug then
		state:debug("FPS CAMERA IS ON!")
	end

	if settings.fps then
		state:debug("FPS:    %i", lt.getFPS())
	end

	if settings.debug then
		state:debug("DELTA:  %ins", lt.getAverageDelta() * 1000000000)
		state:debug("TARGET: %s", state.target_true:round())
		state:debug("EYE:    %s", state.eye:round())

--		for k, v in ipairs(state.colliders:getItems()) do
--			local x, y, z, w, h, d = state.colliders:getCube(v)
--			local scale = vector(w, h, d)
--			local position = vector(x, y, z) + (scale / 2)
--
--			renderer.render {
--				mesh = assets.mod_cube,
--				model = mat4.from_transform(position, 0, scale),
--				color = { 1, 0, 1, 1 / 4 },
--				unshaded = true
--			}
--		end
	end

	for index, entity in ipairs(state.new_entities) do
		entities.init(state.entities, entity, state)
		state.new_entities[index] = nil
	end

	state.entities = entities.tick(state.entities, dt, state)

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
	if not state.resized then
		love.resize(w, h) -- Create one!
		state.resized = true
	end

	lg.reset()

	for _, light in ipairs(state.map_lights) do
		renderer.light(light)
	end

	renderer.draw(w, h, state)

	local r = function()
		lg.push("all")
		assets.shd_post:send("color_a", fam.hex"#00093b")
		assets.shd_post:send("color_b", fam.hex"#ff0080")
		assets.shd_post:send("power",  0.2)
		lg.setShader(assets.shd_post)
		lg.scale(state.scale)

		local canvas = renderer.output()
		canvas:setFilter("nearest")
		lg.draw(canvas)

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
		lg.print("QUITTER...", (w / (state.scale * 2)) - 70)
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