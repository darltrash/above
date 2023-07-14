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
local canvas_temp_a, canvas_temp_b
local canvas_normals_c, canvas_depth_c
local canvas_light_pass = {}
local canvas_shadowmaps

local cuberes = 256

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

local materials = assert(mimi.load("assets/materials.mi"))
log.info("Loaded materials")

for _, material in pairs(materials) do
	if material.shader then
		material.shader = assets["shd_" .. material.shader]
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

	call.order = call.order or 0

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
	if allocated_canvases[1] then
		for index, canvas in ipairs(allocated_canvases) do
			canvas:release()
			allocated_canvases[index] = nil
		end
	end

	local function canvas(t)
		local f = t.filter
		t.filter = nil

		local scale = (scale * (t.scale or 1))
		t.scale = nil

		local w = t.width or math.floor(math.ceil(w / scale) * 2) / 2
		local h = t.height or math.floor(math.ceil(h / scale) * 2) / 2

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
	canvas_color_a:setMipmapFilter("linear")
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

	canvas_color_b   = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "nearest"
	}
	canvas_color_b:setMipmapFilter("linear")
	canvas_normals_b    = canvas {
		format = "rgb10a2",
		mipmaps = "auto",
		filter = "linear"
	}
	canvas_depth_b      = canvas {
		format = "depth24",
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

	canvas_temp_a = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "linear"
	}

	canvas_temp_b = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "linear"
	}

	-- ////////////// SHADOWMAP ////////////

	uniforms.resolution = { w / scale, h / scale }
end

local shadow_maps_res = 2048
uniforms.shadow_maps = { unpack = true }
for i=1, 4 do
	uniforms.shadow_maps[i] = lg.newCanvas(shadow_maps_res, shadow_maps_res, {
		format = "depth24",
		readable = true,
	})

	uniforms.shadow_maps[i]:setFilter("linear", "linear")
	uniforms.shadow_maps[i]:setDepthSampleMode("greater")
	uniforms.shadow_maps[i]:setWrap("clamp", "clamp")
end

canvas_normals_c = lg.newCanvas(cuberes, cuberes, {
	format = "rgb10a2",
	mipmaps = "auto",
})

canvas_depth_c = lg.newCanvas(cuberes, cuberes, {
	format = "depth24",
	mipmaps = "manual",
	readable = true
})


local stars = {}
for x=1, 90 do
	table.insert(stars, vector(
		lm.random(0, 1000) / 1000,
		lm.random(0, 1000) / 1000,
		lm.random(0, 1000) / 1000
	))
end

local function render_stars(w, h)
	for k, v in ipairs(stars) do
		lg.circle("fill", v.x*w, v.y*h, 6)
	end
end


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

		switch               = not switch

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

		lg.setShader(assets.shd_copy)
		assets.shd_copy:send("color", uniforms.back_color)
		assets.shd_copy:send("normal", uniforms.back_normal)
		lg.setDepthMode("always", true)
		lg.draw(uniforms.back_depth)
		lg.pop()
	end

	local c = target.canvas_color or target.canvas_depth

	local width, height = c:getDimensions()

	uniforms.view = target.view
	local eye = vector.from_table(uniforms.view:multiply_vec4({ 0, 0, 0, 1 }))
	uniforms.eye = eye

	uniforms.projection = target.projection or mat4.from_perspective(-45, -width / height, 0.01, 300)
	uniforms.inverse_proj = uniforms.projection:inverse()
	local view_proj = uniforms.projection * uniforms.view

	local view_frustum = frustum.from_mat4(view_proj)

	local lights = 0
	if not target.no_lights then -- Lighting code
		uniforms.ambient = fam.hex("#30298f", 20)
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

			light_list[i] = nil
		end

		uniforms.light_amount = lights
	else
		uniforms.ambient = { 1, 1, 1, 1 }
	end

	if lights == 0 then
		uniforms.light_positions = nil
		uniforms.light_colors = nil
	end

	-- Push the state, so now any changes will only happen locally
	lg.push("all")
	lg.setCanvas {
		target.canvas_color and { target.canvas_color, face = target.face },
		target.canvas_normal and { target.canvas_normal },
		depthstencil = { target.canvas_depth }
	}
	lg.clear(true, true, true)

	lg.setBlendMode("replace") -- NO BLENDING ALLOWED IN MY GAME.

	if not target.no_sky then
		local call = render {
			mesh = assets.mod_sphere.mesh,
			model = mat4.from_transform(eye, 0, 90),
			depth = "lequal",
			material = "sky"
		}

		call.texture:setFilter("linear", "linear")
	end

	lg.setShader(assets.shd_basic)

	local vertices = 0

	--assets.shader:send("dither_table", unpack(uniforms.dither_table))

	local function render(call)
		-- If it has a visibility box, and the box is not visible on screen
		if call.box and not view_frustum:vs_aabb(call.box.min, call.box.max) then
			return false -- Then just ignore it, do not render something not visible
		end

		if target.shadow and call.no_shadow then
			return
		end

		local color = call.color or COLOR_WHITE

		uniforms.clip = call.clip or CLIP_NONE
		uniforms.model = call.model or mat4.identity()
		uniforms.translucent = call.translucent or 0
		uniforms.glow = call.glow or 0

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
		local shader = target.shader or call.shader or assets.shd_basic
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

	local function get_order(call)
		if call.order then
			return call.order
		end

		call.order = 0
		if call.box then
			local origin = (call.box.max + call.box.min) / 2

			call.order = vector.dist(eye, origin)
		end

		return call.order
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

local function generate_cubemap(eye)
	local format = { type = "cube", format = "rg11b10f", mipmaps = "auto" }

	local target = {
		canvas_color_a = uniforms.cubemap or lg.newCanvas(cuberes, cuberes, format),
		canvas_depth_a = canvas_depth_c,
		canvas_normals_a = canvas_normals_c,

		projection = mat4.from_perspective(-90, -1, 0.01, 300)
	}

	local directions = {
		vector(1, 0, 0), vector(-1, 0, 0), -- right vs left
		vector(0, 1, 0), vector(0, -1, 0), -- bottom vs top
		vector(0, 0, 1), vector(0, 0, -1), -- front vs back
	}

	for index, direction in ipairs(directions) do
		local up = vector(0, 1, 0)

		if math.abs(vector.dot(direction, up)) == 1 then
			up = vector(0, 0, 1)
		end

		target.face = index
		target.view = mat4.look_at(0, direction, up)

		render_to(target)
	end

	return target
end

local function generate_ambient()
	local target = generate_cubemap(vector(0, 0, 0))

	uniforms.cubemap = target.canvas_color
	uniforms.cubemap:setFilter("linear", "linear")
end

local function draw(target, state)
	target.canvas_color_a   = canvas_color_a
	target.canvas_depth_a   = canvas_depth_a
	target.canvas_normals_a = canvas_normals_a

	target.canvas_color_b   = canvas_color_b
	target.canvas_depth_b   = canvas_depth_b
	target.canvas_normals_b = canvas_normals_b

--	local width, height = target.canvas_color_a:getDimensions()
--
--	target.projection = mat4.from_perspective(-45, -width / height, 0.01, 300)

	local total_calls = 0
	if target.sun and false then
		local shadow = {
			split_count = 4,
			distance = 100,
			split_distribution = 0.95,
			stabilize = true,
			res = shadow_maps_res
		}

		local inv_view = target.view:inverse()
		local proj = target.projection
		local c = csm.setup_csm(shadow, -target.sun:normalize(), inv_view, proj)

		uniforms.shadow_matrix = {
			unpack = true
		}

		for index=1, 4 do
			local shadow = {
				view = c.lights[index],
				projection = mat4.identity(),

				no_lights = true,
				no_cleanup = true,
				no_sky = true,
				shadow = true,

				canvas_depth_a = uniforms.shadow_maps[index],

				shader = assets.shd_none
			}

			local vertices, calls, grabs = render_to(shadow)
			total_calls = total_calls + calls

			table.insert(uniforms.shadow_matrix, shadow.view:inverse():to_columns())

			--if index == 4 then
			--	target.view = shadow.view
			--	target.projection = mat4.identity()
			--	target.no_sky = true
			--end
		end
	end

	if target.shadow_view then
		local shadow = {
			view = target.shadow_view,
			projection = mat4.from_ortho(-15, 15, -10, 10, -1000, 1000),

			no_lights = true,
			no_cleanup = true,
			no_sky = true,
			shadow = true,

			culling = "none",

			canvas_depth_a = uniforms.shadow_maps[1],

			shader = assets.shd_none
		}

		local vertices, calls, grabs = render_to(shadow)
		total_calls = total_calls + calls

		uniforms.shadow_view = shadow.view
		uniforms.shadow_projection = shadow.projection
		uniforms.shadow_map = shadow.canvas_depth

		if false then
			target.view = shadow.view
			target.projection = shadow.projection
			target.shader = assets.shd_none
			target.no_sky = true
			target.shadow = true
			target.culling = "none"
			target.shader = assets.shd_none
		end
	end

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
	lg.push("all")
		lg.setCanvas(canvas_light_pass)
		lg.setShader(assets.shd_light)
		assets.shd_light:send("exposure", target.exposure)
		lg.clear(0, 0, 0, 0)
		target.canvas_color:setFilter("linear", "linear")
		lg.draw(target.canvas_color, 0, 0, 0, 0.5)
	lg.pop()

	lg.push("all")
		lg.setBlendMode("replace", "premultiplied")
		lg.setCanvas(canvas_temp_a)
		lg.draw(canvas_light_pass)

		lg.setCanvas(canvas_temp_b)
		canvas_temp_a:generateMipmaps()

		lg.setShader(assets.shd_blur_mip)
		for i=1, canvas_temp_a:getMipmapCount() do
			lg.setCanvas(canvas_temp_b, i)
			assets.shd_blur_mip:send("direction_mip", {1, 0, i})
			lg.draw(canvas_temp_a, -1, -1)
		end

		for i=1, canvas_temp_a:getMipmapCount() do
			lg.setCanvas(canvas_temp_a, i)
			assets.shd_blur_mip:send("direction_mip", {0, 1, i})
			lg.draw(canvas_temp_b, -1, -1)
		end

		lg.setCanvas(canvas_light_pass)
		lg.setShader(assets.shd_accum_mip)
		assets.shd_accum_mip:send("mip_count", canvas_temp_a:getMipmapCount()-1)
		lg.draw(canvas_temp_a)
	lg.pop()

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
