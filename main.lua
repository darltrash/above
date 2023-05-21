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
_G.lg = love.graphics
_G.lm = love.math
_G.la = love.audio
_G.lt = love.timer

la.setVolume(tonumber(settings.volume) or 1)

local assets = require "assets"
local entities = require "entity"
local renderer = require "renderer"

local state = {
	entities = {},

	settings = settings,

	target = vector.zero:copy(),
	target_true = vector.zero:copy(),

	scale = 2, zoom = 1,
	escape = 0, transition = 1,

	transition_speed = 0,
	transition_callback = function ()
		print("test test test")
	end,

	debug_lines = {},

	debug = function (self, str, ...)
		table.insert(self.debug_lines, str:format(...))
	end
}

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
		what, #state.map_lights, #state.entities, #meta.trigger_areas
	)
end

load_map(settings.level or "mod_forest")

local avg_values = {}

-- Handle window resize and essentially canvas (destruction and re)creation
function love.resize(w, h)
	-- Do some math and now we have a generalized scale for each pixel
	state.scale = tonumber(settings.scale) or math.max(1, math.floor(math.min(w, h)/300))

	renderer.resize(w, h, state.scale)

	effect.resize(w, h)
	effect.scanlines.frequency = h / state.scale
	effect.chromasep.radius = state.scale
end

function love.keypressed(k)
	if (k == "f11") then
		settings.fullscreen = not settings.fullscreen
		log.info("Fullscreen %s", settings.fullscreen and "enabled" or "disabled")
		love.window.setFullscreen(settings.fullscreen)
		love.resize(lg.getDimensions())
	elseif (k == "f3") then -- DO NOT USE THIS
		local avg = 0
		for _, v in ipairs(avg_values) do
			avg = avg + v
		end
		log.info("sexo: %i", avg / #avg_values)
	end
end

function love.update(dt)
	-- Checks for updates in all configured input methods (Keyboard + Joystick)
	input:update()

	-- Useful for shaders :)
	renderer.uniforms.time = (renderer.uniforms.time or 0) + dt
	renderer.uniforms.view = mat4.look_at(vector(0, 2, -6) + state.target, state.target, { y = 1 })
	renderer.uniforms.frame = (renderer.uniforms.frame or 0) + 1

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

		renderer.uniforms.view = renderer.uniforms.view *
			mat4.from_transform(offset * 0.05 * 0.5, rot * 0.05 * 0.5, state.zoom)

	end

	state.eye = vector.from_table(renderer.uniforms.view:multiply_vec4 {0, 0, 0, 1})

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
				unshaded = buffer.material:match("unshaded"),
				range = {buffer.first, buffer.last - buffer.first},
				texture = buffer.material:match("general")
					and assets.general or state.map.texture
			}
		end

		renderer.render {
			mesh = assets.water_mesh,
			color = fam.hex("#823be5"),
			model = mat4.from_transform(pos, 0, 60),
			order = math.huge,
			shader = assets.shader_water,
		}
	end

	if settings.fps then
		state:debug("FPS:    %i", lt.getFPS())
	end

	if settings.debug then
		state:debug("DELTA:  %ins", lt.getAverageDelta() * 1000000000)
		state:debug("TARGET: %s", state.target_true:round())
		state:debug("EYE:    %s", state.eye:round())

		for k, v in ipairs(state.colliders:getItems()) do
			local x, y, z, w, h, d = state.colliders:getCube(v)
			local scale = vector(w, h, d)
			local position = vector(x, y, z) + (scale / 2)

			renderer.render {
				mesh = assets.cube,
				model = mat4.from_transform(position, 0, scale),
				color = {1, 0, 1, 1/4},
				unshaded = true
			}
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

local resized

function love.draw()
	-- If the canvas hasnt been created yet
	local w, h = lg.getDimensions()
	if not resized then
		love.resize(w, h) -- Create one!
		resized = true
	end

	lg.reset()
	
	for _, light in ipairs(state.map_lights) do
		renderer.light(light)
	end
	
	renderer.draw(w, h, state)

	local r = function ()
		lg.push("all")
			lg.setShader(assets.shader_post)
			lg.scale(state.scale)

			local canvas = renderer.output()
			lg.draw(canvas)

			lg.setShader()
			lg.setBlendMode("alpha")
			lg.setFont(assets.font)
			for i, v in ipairs(state.debug_lines) do
				lg.print(v, 4, 8*(i-1))

				state.debug_lines[i] = nil
			end

			lg.scale(2)
			lg.setColor(0, 0, 0, state.escape*state.escape)
			lg.rectangle("line", (w/(state.scale*2)) - 73, 2, w, 12)
			lg.setColor(0, 0, 0, 1)
			lg.rectangle("fill", (w/(state.scale*2)) - 73, 2, w, 12*(state.escape*state.escape))
			lg.setColor(1, 1, 1, state.escape*state.escape)
			lg.print("QUITTER...", (w/(state.scale*2)) - 70)
		lg.pop()
	end

	if settings.no_post then
		r()
	else
		effect(r)
	end
	
end