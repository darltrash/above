local assets = require "assets"
local fam = require "fam"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"
local mimi = require "lib.mimi"
local log = require "lib.log"
local frustum = require "frustum"
local json = require "lib.json"
local csm = require "csm"

local render_list = {}
local grab_list = {}
local light_list = {}

local canvas_flat

local canvas_color_a, canvas_normals_a, canvas_depth_a
local canvas_color_b, canvas_normals_b, canvas_depth_b
local canvas_temp_a,  canvas_temp_b,    canvas_temp_s
local canvas_reflection
local canvas_normals_c, canvas_depth_c
local canvas_light_pass = {}
local canvas_depth_s

local cuberes = 64

-- CONSTANTS
local COLOR_WHITE = { 1, 1, 1, 1 }
local COLOR_BLACK = { 0, 0, 0, 1 }
local CLIP_NONE = { 0, 0, 1, 1 }

-- This mechanism right here allows me to share uniforms in between
-- shaders AND automatically update them to reduce boilerplate.
local uniform_map = {}
local uniforms = {
	perlin = assets.tex_perlin,
	stars = assets.tex_stars,

	sun_gradient = assets.tex_sky_sun_gradient
}

uniforms.perlin:setFilter("linear", "linear")
uniforms.sun_gradient:setFilter("linear", "linear")

local materials = assert(mimi.load("assets/materials.mi"))
log.info("Loaded materials")

for _, material in pairs(materials) do
	if material.shader_true then
		material.shader = assets["shd_" .. material.shader_true]
	elseif material.shader then
		material.shader = assets["shk_" .. material.shader]
	end

	if material.texture then
		material.texture = assets["tex_" .. material.texture]
	end
end

local function render(call)
	if call.ignore then
		return call
	end

	if call.material then
		for _, name in ipairs(fam.split(call.material, ".")) do
			local mat = materials[name]
			if mat then
				fam.copy_into(mat, call)
			end
		end
	end

	local m = call.mesh
	if type(m) == "table" then
		call.mesh = m.mesh

		call.box = {
			min = m.bounds.base.min,
			max = m.bounds.base.max
		}
	end

	if call.box and call.model then
		local function a(m)
			m.w = 1
			return vector.from_table(call.model:multiply_vec4(m))
		end

		call.box = {
			min = a(call.box.min),
			max = a(call.box.max)
		}
	end

	if call.shader then
		call.grab =
			call.shader:hasUniform("back_color")  or
			call.shader:hasUniform("back_normal") or
			call.shader:hasUniform("back_depth")
	end

	if call.grab then
		table.insert(grab_list, call)

		return call
	end

	table.insert(render_list, call)

	return call
end

local l_counter = 0
local function light(light)
	table.insert(light_list, light)
end

local function uniform_update(shader)
	uniform_map[shader] = uniform_map[shader] or {}
	local map = uniform_map[shader]

	for k, v in pairs(uniforms) do
		if map[k] ~= v and shader:hasUniform(k) then
			if mat4.is_mat4(v) then
				shader:send(k, "column", v:to_columns())
			elseif vector.is_vector(v) then
				shader:send(k, v:to_array())
			elseif type(v) == "table" and v.unpack then
				shader:send(k, unpack(v))
			else
				shader:send(k, v)
			end
		end
		map[k] = v
	end
end

canvas_flat = lg.newCanvas(128, 128)
canvas_flat:setFilter("nearest", "nearest")

local allocated_canvases = {}

local function resize(w, h, scale)
	-- If the canvases already exist, YEET THEM OUT (safely).
	for index, canvas in ipairs(allocated_canvases) do
		canvas:release()
		allocated_canvases[index] = nil
	end

	local function canvas(t)
		local f = t.filter
		t.filter = nil

		local scale = (scale * (t.scale or 1))
		t.scale = nil

		local w = t.width  or math.ceil(w / scale)
		local h = t.height or math.ceil(h / scale)

		t.width = nil
		t.height = nil

		local c = lg.newCanvas(w, h, t)
		if f then
			c:setFilter(f, f)
		end

		table.insert(allocated_canvases, c)

		return c
	end

	-- ////////////// A CANVAS /////////////

	canvas_color_a = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "nearest"
	}
	canvas_normals_a = canvas {
		format = "rgb10a2",
		mipmaps = "auto",
		filter = "linear"
	}
	canvas_depth_a   = canvas {
		format = "depth24",
		mipmaps = "manual",
		readable = true,
		filter = "linear"
	}

	-- ////////////// B CANVAS /////////////

	canvas_color_b = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "nearest"
	}
	canvas_normals_b = canvas {
		format = "rgb10a2",
		mipmaps = "auto",
		filter = "linear"
	}
	canvas_depth_b = canvas {
		format = "depth24",
		mipmaps = "manual",
		readable = true,
		filter = "linear"
	}
	
	-- ////////////// REFLECTION ///////////

	canvas_reflection = canvas {
		format = "rg11b10f",
		mipmaps = "manual",
		readable = true,
		filter = "linear"
	}

	-- ////////////// LIGHT PASS ///////////

	canvas_light_pass = canvas {
		scale = 2,
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "linear"
	}

	-- ////////////// TEMPORARY /////////////

	canvas_temp_a = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "linear"
	}
	canvas_temp_a:setMipmapFilter("linear")

	canvas_temp_b = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "linear"
	}
	canvas_temp_b:setMipmapFilter("linear")

	-- ////////////// SHADOWMAP ////////////

	uniforms.resolution = {
		math.ceil(w / scale),
		math.ceil(h / scale)
	}
end

local shadow_maps_res = 1024
local shadow_msaa = 0
uniforms.shadow_maps = { unpack = true }
for i=1, 4 do
	uniforms.shadow_maps[i] = lg.newCanvas(
		shadow_maps_res, shadow_maps_res, {
		format = "r16f"
	})

	uniforms.shadow_maps[i]:setFilter("linear", "linear")
end

canvas_temp_s = lg.newCanvas(
	shadow_maps_res, shadow_maps_res, {
	format = "rg16f",
	msaa = shadow_msaa
})

canvas_temp_s:setFilter("linear", "linear")

canvas_depth_s = lg.newCanvas(shadow_maps_res, shadow_maps_res, {
	format = "depth24",
	msaa = shadow_msaa
})

canvas_normals_c = lg.newCanvas(cuberes, cuberes, {
	format = "rgb10a2",
	mipmaps = "auto",
})

canvas_depth_c = lg.newCanvas(cuberes, cuberes, {
	format = "depth24",
	mipmaps = "manual",
	readable = true
})


local function render_to(target)
	local switch         = false
	target.canvas_color  = target.canvas_color_a
	target.canvas_depth  = target.canvas_depth_a
	target.canvas_normal = target.canvas_normals_a

	local function grab()
		-- Does not have a swappable canvas, ignore.
		if not target.canvas_color_b then
			return
		end

		lg.push("all")
			uniforms.back_color  = target.canvas_color
			uniforms.back_depth  = target.canvas_depth
			uniforms.back_normal = target.canvas_normal

			switch = not switch

			target.canvas_color  = switch
				and target.canvas_color_b or target.canvas_color_a

			target.canvas_depth  = switch
				and target.canvas_depth_b or target.canvas_depth_a

			target.canvas_normal = switch
				and target.canvas_normals_b or target.canvas_normals_a

			lg.setCanvas {
				target.canvas_color and { target.canvas_color, face = target.face },
				target.canvas_normal and { target.canvas_normal },
				depthstencil = { target.canvas_depth }
			}

			lg.clear(true, true, true)
			lg.setColor(COLOR_WHITE)
			lg.setDepthMode("always", true)

			lg.setShader(assets.shd_copy)
			assets.shd_copy:send("color", uniforms.back_color)
			assets.shd_copy:send("normal", uniforms.back_normal)

			lg.draw(uniforms.back_depth)
		lg.pop()
	end

	local c = target.canvas_color or target.canvas_depth

	local width, height = c:getDimensions()

	uniforms.view = target.view
	local eye = vector.from_table(uniforms.view:multiply_vec4({ 0, 0, 0, 1 }))
	uniforms.eye = eye

	uniforms.projection = target.projection or mat4.from_perspective(45, width / height, 0.01, 300)
	uniforms.inverse_proj = uniforms.projection:inverse()

	uniforms.inverse_view = target.view:inverse()
	local view_proj = uniforms.projection * uniforms.view

	local view_frustum = frustum.from_mat4(view_proj)

	local lights = 0
	if not target.no_lights then -- Lighting code
		uniforms.light_positions = { unpack = true }
		uniforms.light_colors = { unpack = true }

		for i, light in ipairs(light_list) do -- ONLY 16 LIGHTS MAX!
			if view_frustum:vs_sphere(light.position, light.color[4]) then
				local pos = light.position:to_array()
				pos.w = 1

				uniforms.light_positions[(lights%16)+1] = pos
				uniforms.light_colors[(lights%16)+1] = light.color
				
				lights = lights + 1
			end

			if not target.no_cleanup then
				light_list[i] = nil
			end
		end

		uniforms.light_amount = lights
	else
		uniforms.ambient = { 1, 1, 1, 1 }
	end

	if lights == 0 then
		uniforms.light_positions = nil
		uniforms.light_colors = nil
	end

	uniforms.trim = target.reflection_pass or false

	-- Push the state, so now any changes will only happen locally
	lg.push("all")
	lg.setCanvas {
		target.canvas_color and { target.canvas_color, face = target.face },
		target.canvas_normal and { target.canvas_normal },
		depthstencil = { target.canvas_depth }
	}
	if target.clear ~= false then
		lg.clear(target.clear or true, true, true, true, true, true, true)
	end

	lg.setBlendMode("replace") -- NO BLENDING ALLOWED IN MY GAME.

	if not target.no_sky then
		render {
			mesh = assets.mod_sphere.mesh,
			model = mat4.from_transform(eye*vector(1, 0, 1), 0, 200),
			shader = assets.shd_cubemap,
			culling = "front"
		}
	end

	lg.setShader(assets.shk_basic)

	local vertices = 0

	--assets.shader:send("dither_table", unpack(uniforms.dither_table))

	local function render(call)
		-- If it has a visibility box, and the box is not visible on screen
		if call.box and not view_frustum:vs_aabb(call.box.min, call.box.max) then
			return false -- Then just ignore it, do not render something not visible
		end

		if target.shadow and call.no_shadow then
			return false
		end

		local color = call.color or COLOR_WHITE

		uniforms.clip = call.clip or CLIP_NONE
		uniforms.model = call.model or mat4.identity()
		uniforms.translucent = call.translucent or 0
		uniforms.glow = call.glow or 0
		uniforms.grid_mode = call.grid_mode and 1 or 0

		-- Just so i can abstract away the IQM/EXM types :)
		local mesh = call.mesh
		if type(mesh) == "table" then
			mesh = mesh.mesh
		end

		if call.texture then
			-- Off-screen texture generation callback
			if type(call.texture) == "function" then
				lg.push("all")
				lg.reset()
				lg.setCanvas(canvas_flat)
				lg.clear(0, 0, 0, 0)
				lg.setColor(1, 1, 1, 1)
				call:texture()
				lg.pop()

				mesh:setTexture(canvas_flat)
			else
				mesh:setTexture(call.texture)
			end
		end

		local v = mesh:getVertexCount()
		if call.range then
			mesh:setDrawRange(unpack(call.range))
			v = call.range[2]
		end

		-- Default to basic shader
		local shader = target.shader or call.shader or assets.shk_basic
		if call.grab and not target.shader then
			grab()
		end

		-- Set the fricken canvas
		lg.setCanvas {
			target.canvas_color and { target.canvas_color, face = target.face },
			target.canvas_normal and { target.canvas_normal },
			depthstencil = { target.canvas_depth }
		}
		lg.setDepthMode(call.depth or "less", true)
		lg.setMeshCullMode(target.culling or call.culling or "back")

		lg.setColor(color)

		uniform_update(shader)
		lg.setShader(shader)

		lg.draw(mesh)

		mesh:setDrawRange()

		vertices = vertices + v

		return true
	end

	local order_cache = {}

	local function get_order(call)
		if not order_cache[call] then
			local order = 0

			local box = call.box
			if box then
				local origin = box.min + (box.max / 2)

				order = vector.dist(eye, origin)
			end

			order_cache[call] = order
		end

		return order_cache[call]
	end

	----------------------------------------------

	local calls = 0
	table.sort(render_list, function(a, b)
		return get_order(a) > get_order(b)
	end)

	for index, call in ipairs(render_list) do
		if render(call) then
			calls = calls + 1
		end

		render_list[index] = target.no_cleanup
			and render_list[index] or nil
	end

	----------------------------------------------

	local grab_calls = 0
	table.sort(grab_list, function(a, b)
		return get_order(a) < get_order(b)
	end)

	for index, call in ipairs(grab_list) do
		if render(call) then
			grab_calls = grab_calls + 1
		end

		grab_list[index] = target.no_cleanup
			and grab_list[index] or nil
	end

	lg.pop()

	return vertices, calls, grab_calls, lights
end

-- Create cubemap of world
local function generate_cubemap()
	local format = { type = "cube", format = "rg11b10f" }

	local target = {
		canvas_color_a = uniforms.cubemap or lg.newCanvas(cuberes, cuberes, format),
		canvas_depth_a = canvas_depth_c,
		no_sky = true,
		no_cleanup = true,

		projection = mat4.from_perspective(-90, -1, 0.01, 300),
		clear = false
	}

	local directions = {
		vector(1, 0, 0), vector(-1, 0, 0), -- right vs left
		vector(0, 1, 0), vector(0, -1, 0), -- bottom vs top
		vector(0, 0, 1), vector(0, 0, -1), -- front vs back
	}

	local call = render {
		mesh = assets.mod_sphere.mesh,
		model = mat4.from_transform(0, 0, 1),
		material = "sky",
		depth = "always"
	}

	call.texture:setFilter("linear", "linear")

	for index, direction in ipairs(directions) do
		local up = vector(0, 1, 0)

		if math.abs(vector.dot(direction, up)) == 1 then
			up = vector(0, 0, 1)
		end

		target.face = index
		target.view = mat4.look_at(0, direction, up)

		render_to(target)
	end

	render_list = {}

	return target
end

local function generate_ambient()
	local target = generate_cubemap()

	uniforms.cubemap = target.canvas_color
	uniforms.cubemap:setFilter("linear", "linear")
end

-- b: temporary
local function blur(a, b, p)
	p = p or 1

	lg.push("all")
		lg.setShader(assets.shd_box_blur)
		lg.setColor(1, 1, 1, 0.5)

		lg.setCanvas(b)
		lg.clear(1, 1, 1, 1)
		assets.shd_box_blur:send("direction", {0, p})
		lg.draw(a)

		lg.setCanvas(a)
		lg.clear(1, 1, 1, 1)
		assets.shd_box_blur:send("direction", {p, 0})
		lg.draw(b)
	lg.pop()
end

local function draw(target, state)
	target.canvas_color_a   = canvas_color_a
	target.canvas_depth_a   = canvas_depth_a
	target.canvas_normals_a = canvas_normals_a

	target.canvas_color_b   = canvas_color_b
	target.canvas_depth_b   = canvas_depth_b
	target.canvas_normals_b = canvas_normals_b

	local width, height = target.canvas_color_a:getDimensions()

	target.projection = mat4.from_perspective(-45, -width / height, 0.01, 300)

	local total_calls = 0

	if target.sun then -- Shadow mapping
		local setup = {
			split_count = 1,
			distance = 100,
			split_distribution = 0.95,
			stabilize = false,
			res = shadow_maps_res
		}

		local inv_view = target.view:inverse()
		local proj = target.projection
		local c = csm.setup_csm(setup, -target.sun, inv_view, proj)

		uniforms.shadow_mats = {
			unpack = true
		}

		for x=1, 1 do
			local shadow = {
				view = target.shadow_view,
				projection = mat4.from_ortho(-30, 30, -30, 30, -2, 512),

				no_lights = true,
				no_cleanup = true,
				no_sky = true,
				shadow = true,

				culling = "none",

				canvas_color_a = uniforms.shadow_maps[x],
				canvas_depth_a = canvas_depth_s,

				shader = assets.shd_shadowmapper,
				clear = COLOR_WHITE
			}

			local vertices, calls, grabs = render_to(shadow)
			total_calls = total_calls + calls

			blur(shadow.canvas_color, canvas_temp_s, 1)
			
			--uniforms.shadow_mats[x] = (shadow.projection * shadow.view):to_columns()
			uniforms.shadow_proj = shadow.projection
			uniforms.shadow_view = shadow.view
		end
	end

	if target.reflection then
		-- canvas_reflection
		local reflection = {
			view = target.reflection,
			projection = target.projection,
			no_cleanup = true,
			shadow = true,

			canvas_color_a   = canvas_reflection,
			canvas_depth_a   = canvas_depth_a,

			reflection_pass = true,

			clear = COLOR_WHITE
		}

		local vertices, calls, grabs = render_to(reflection)

		--lg.push("all")
		--	lg.setCanvas(canvas_reflection)
		--	lg.clear(0, 0, 0, 0)
		--	lg.draw(reflection.canvas_color)
		--lg.pop()

		uniforms.reflection = canvas_reflection
		uniforms.reflection_matrix = reflection.view

		total_calls = total_calls + calls
	end

	target.clear = true

	local vertices, calls, grabs, lights = render_to(target)
	total_calls = total_calls + calls

	if state.settings.debug then
		state:debug("")
		state:debug("--- RENDERER -----")
		state:debug("VERTS:  %i", vertices)
		state:debug("CALLS:  %i", calls)
		state:debug("GRABS:  %i", grabs)
		state:debug("LIGHTS: %i/16", lights)
		state:debug("")
		state:debug("TCALLS: %i/200", total_calls)
	end
	
	target.exposure = -6.5

	-- Generate light threshold data :)
--	lg.push("all")
--		lg.setCanvas(canvas_light_pass)
--		lg.setShader(assets.shd_light)
--		assets.shd_light:send("exposure", target.exposure)
--		lg.clear(0, 0, 0, 0)
--		target.canvas_color:setFilter("linear", "linear")
--		lg.draw(target.canvas_color, 0, 0, 0, 0.5)
--	lg.pop()

--	lg.push("all") -- Mipmap blur for the bloom effect :)
--		lg.setBlendMode("replace", "premultiplied")
--
--		lg.setCanvas(canvas_temp_a)
--		lg.draw(canvas_light_pass)
--
--		lg.setCanvas(canvas_temp_b)
--		canvas_temp_a:generateMipmaps()
--
--		lg.setShader(assets.shd_blur_mip)
--		for i=1, canvas_temp_a:getMipmapCount() do
--			lg.setCanvas(canvas_temp_b, i)
--			assets.shd_blur_mip:send("direction_mip", {1, 0, i})
--			lg.draw(canvas_temp_a, -1, -1)
--		end
--
--		for i=1, canvas_temp_a:getMipmapCount() do
--			lg.setCanvas(canvas_temp_a, i)
--			assets.shd_blur_mip:send("direction_mip", {0, 1, i})
--			lg.draw(canvas_temp_b, -1, -1)
--		end
--
--		lg.setCanvas(canvas_light_pass)
--		lg.setShader(assets.shd_accum_mip)
--		assets.shd_accum_mip:send("mip_count", canvas_temp_a:getMipmapCount()-1)
--
--		lg.draw(canvas_temp_a)
--	lg.pop()

	--blur(canvas_light_pass, canvas_temp_b)

	target.canvas_color:setFilter("nearest", "nearest")

	target.canvas_light_pass = canvas_light_pass

	-- return it allll
	return target
end

return {
	draw = draw,
	render = render,
	light = light,
	resize = resize,

	uniforms = uniforms,
	generate_ambient = generate_ambient
}
