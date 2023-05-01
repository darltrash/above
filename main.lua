local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local rmap = require "lib.map"
local input = require "input"
local fam = require "fam"

-- SOME SETTINGS (sadly it uses env vars)
local settings = {}
do
	settings.debug = os.getenv("ABOVE_DEBUG")
	settings.fps = os.getenv("ABOVE_FPS") or settings.debug
	settings.linear = os.getenv("ABOVE_LINEAR") -- cursed mode
end

if not settings.linear then
	love.graphics.setDefaultFilter("nearest", "nearest")
end

-- GLOBALS!
local COLOR_WHITE = {1, 1, 1, 1}
local CLIP_NONE = {0, 0, 1, 1}
_G.lg = love.graphics
_G.lm = love.math
_G.lt = love.timer

--local music = love.audio.newSource("assets/mus_brothermidi.mp3", "static")
--music:setLooping(true)
--music:play()

local water_mesh = rmap("assets/mod_water.mod").mesh

local state = {
	scale = 2,
	target = vector.zero:copy(),
	target_true = vector.zero:copy(),
	canvas_switcheroo = false
}

local shader = lg.newShader "assets/shd_basic.glsl"
local font = lg.newFont("assets/fnt_monogram.ttf", 16)
local atlas = lg.newImage("assets/atl_main.png")
local quad_model = rmap("assets/mod_quad.mod").mesh
quad_model:setTexture(atlas)

local function load_map(what)
	if state.map_mesh then
		state.map_mesh:release()
		state.map_texture:release()
	end

	local map = rmap(("assets/%s.mod"):format(what))
	state.map_mesh = map.mesh
	state.map_texture = lg.newImage(("assets/%s.png"):format(what))
	state.map_mesh:setTexture(state.map_texture)
end

load_map("mod_thing")

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

-- Handle window resize and essentially canvas (destruction and re)creation
function love.resize(w, h)
	-- Do some math and now we have a generalized scale for each pixel
	state.scale = math.max(1, math.floor(math.min(w, h)/300))

	-- If the canvases already exist, YEET THEM OUT (safely).
	if state.canvas_main_a then
		state.canvas_main_a:release()
		state.canvas_depth_a:release()

		state.canvas_main_b:release()
		state.canvas_depth_b:release()
	end

    state.canvas_main_a  = lg.newCanvas(w/state.scale, h/state.scale, { format = "rgba8", msaa=1 })
    state.canvas_depth_a = lg.newCanvas(w/state.scale, h/state.scale, { format = "depth32f", readable = true, msaa=1 })
    state.canvas_normal_a = lg.newCanvas(w/state.scale, h/state.scale, { format = "rgba8", msaa=1 })

	-- // TODO: DO GRAB PASS STUFF ////////
	state.canvas_main_b  = lg.newCanvas(w/state.scale, h/state.scale, { format = "rgba8", msaa=1 })
    state.canvas_depth_b = lg.newCanvas(w/state.scale, h/state.scale, { format = "depth32f", readable = true, msaa=1 })
    state.canvas_normal_a = lg.newCanvas(w/state.scale, h/state.scale, { format = "rgba8", msaa=1 })

	--uniforms.resolution = {w/state.scale, h/state.scale}
end

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
		sprite = {0, 0, 32, 32},
		position = vector(0, 0, 0),
		rotation = vector(0, 0, 0),
		velocity = vector(0, 0, 0),
		camera_target = true,
		controller = "player"
	}
}

-- // NOTE: The light area is encoded within the "length"
--          of the (vec3) color variable multiplied by it's W/[4]
local lights = {
	{
		color = {2, 0, 0, 1},
		position = vector(-1, 1, 0)
	},

	{
		color = {0, 2, 0, 1},
		position = vector(0, 1, 0)
	},

	{
		color = {0, 0, 2, 1},
		position = vector(1, 1, 0)
	}
}

local debug_lines = {} -- Debug stuff!

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

	-- Process entities
	for _, entity in ipairs(entities) do
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

			entity.camera_target = true
		end

		-- // TODO: Implement fixed timesteps
		if entity.velocity then -- Euler integration
			entity.position = entity.position + entity.velocity * dt
		end

		if entity.camera_target then
			state.target_true = entity.position
		end

		:: continue ::
	end

	state.target = state.target:decay(state.target_true, 1, dt)
end

function love.draw()
	-- If the canvas hasnt been created yet
	local w, h = lg.getDimensions()
	if not state.canvas_main_a then
		love.resize(w, h) -- Create one!
	end

	debug_lines = {} -- Clean out the debug lines

	do -- Lighting code
		uniforms.ambient = {0.5, 0.5, 0.7, 1.0}
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

	if settings.fps then
		table.insert(debug_lines, 
			("FPS:    %i"):format(lt.getFPS())
		)
	end

	if settings.debug then
		table.insert(debug_lines, 
			("DELTA:  %ins"):format(lt.getAverageDelta() * 1000000000)
		)

		table.insert(debug_lines, 
			("TARGET: %s"):format(state.target_true)
		)
	end

	-- Push the state, so now any changes will only happen locally
	lg.push("all")
		-- Set the current canvas
		lg.setCanvas({ state.canvas_main_a, depth = state.canvas_depth_a })
		lg.clear({ 0x4f/255, 0x0a/255, 0xb0/255, 1 }, true, true)
		lg.setShader(shader)
		lg.setDepthMode("less", true)
		lg.setMeshCullMode("front")
		lg.setBlendMode("replace")
		
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

		lg.setColor(1, 1, 1, 1)
		uniforms.model = mat4 -- RESET MODEL!
		uniform_update(shader) -- SET UNIFORMS!
		lg.draw(state.map_mesh) -- Render level.

		for _, entity in ipairs(entities) do
			if entity.position then
				lg.setColor(entity.tint or COLOR_WHITE)

				uniforms.model = mat4.from_transform(entity.position, entity.rotation or 0, entity.scale or 1)
				
				if entity.mesh then
					lg.setMeshCullMode("front")

					uniform_update(shader)
					lg.draw(entity.mesh)
				end

				if entity.sprite then
					lg.setMeshCullMode("none")

					uniforms.clip = {
						entity.sprite[1] / atlas:getWidth(),
						entity.sprite[2] / atlas:getHeight(),
						entity.sprite[3] / atlas:getWidth(),
						entity.sprite[4] / atlas:getHeight(),
					}
					uniform_update(shader)
					
					lg.draw(quad_model)
					uniforms.clip = CLIP_NONE
				end
			end
		end

		do -- Render water
			lg.setColor(0x9d/255, 0x3b/255, 0xe5/255, 1)
			-- Always render water close to the camera (it makes the water seem infinite)
			local pos = state.target:copy()
			pos.y = -1.5
			uniforms.model = mat4.from_transform(pos, 0, 20)
			uniform_update(shader)
			lg.draw(water_mesh)
		end

		--lg.setCanvas({ state.canvas_main_b, depth = state.canvas_depth_b })
		--lg.clear(true, true, true)
		--lg.setShader(canvas_copy)
		--lg.setDepthMode("always", true)
		--uniforms.canvas = state.canvas_main_a
		--uniform_update(canvas_copy)
		--lg.draw(state.canvas_depth_a)
	lg.pop()

	lg.draw(state.canvas_main_a, 0, 0, 0, state.scale)

	lg.scale(2)
	lg.setFont(font)
	for i, v in ipairs(debug_lines) do
		lg.print(v, 4, 8*(i-1))
	end
end