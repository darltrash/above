local assets = require "assets"
local fam = require "fam"
local mat4 = require "lib.mat4"
local vector = require "lib.vec3"

local render_list = {}
local grab_list = {}
local light_list = {}

local canvas_flat

local canvas_color_a, canvas_normals_a, canvas_depth_a
local canvas_color_b, canvas_normals_b, canvas_depth_b
local canvas_color,   canvas_normal,    canvas_depth   -- Current canvas

local canvas_switch

-- CONSTANTS
local COLOR_WHITE = {1, 1, 1, 1}
local COLOR_BLACK = {0, 0, 0, 1}
local CLIP_NONE = {0, 0, 1, 1}

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

local function render(call)
	if not call.order then
		call.order = 0

        -- TODO: FIX THIS BULLSHIT:
		-- if call.model then
		-- 	local position = call.model:multiply_vec4({0, 0, 0, 1})
		-- 	call.order = state.eye:dist(position)
		-- end
	end

	if call.shader then
		return table.insert(grab_list, call)
	end

	table.insert(render_list, call)
end

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
			elseif type(v) == "table" and v.unpack then
				shader:send(k, unpack(v))
			else
				shader:send(k, v)
			end
		end
		map[k] = v
	end
end

local function resize(w, h, scale)
    -- If the canvases already exist, YEET THEM OUT (safely).
	if canvas_color_a then
        canvas_flat:release()
		
		canvas_normals_a:release()
		canvas_color_a:release()
		canvas_depth_a:release()

		canvas_normals_b:release()
		canvas_color_b:release()
		canvas_depth_b:release()
	end

	canvas_flat = lg.newCanvas(128, 128)

	local function canvas(t)
		local f = t.filter
		t.filter = nil

		local w = math.floor(math.ceil(w/scale) * 2) / 2
		local h = math.floor(math.ceil(h/scale) * 2) / 2
		local c = lg.newCanvas(w, h, t)
		if f then
			c:setFilter(f, f)
		end

		return c
	end

	-- ////////////// A CANVAS /////////////

	canvas_color_a  = canvas {
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
    canvas_depth_a = canvas {
		format = "depth24",
		mipmaps = "manual",
		readable = true,
		filter = "linear"
	}

	-- ////////////// B CANVAS /////////////

	canvas_color_b  = canvas {
		format = "rg11b10f",
		mipmaps = "auto",
		filter = "nearest"
	}
	canvas_color_b:setMipmapFilter("linear")
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
end

local function switch_canvas()
    lg.push("all")
        uniforms.back_color  = canvas_color
        uniforms.back_depth  = canvas_depth
        uniforms.back_normal = canvas_normal

        canvas_switch = not canvas_switch

        canvas_color = canvas_switch
            and canvas_color_b or canvas_color_a
        
        canvas_depth  = canvas_switch
            and canvas_depth_b or canvas_depth_a

        canvas_normal = canvas_switch
            and canvas_normals_b or canvas_normals_a

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

local function render_scene(w, h)
	canvas_switch = false
	canvas_color  = canvas_color_a
	canvas_depth  = canvas_depth_a
	canvas_normal = canvas_normals_a

	uniforms.projection = mat4.from_perspective(-45, -w/h, 0.01, 1000)
	uniforms.inverse_proj = uniforms.projection:inverse()

	-- Push the state, so now any changes will only happen locally
	lg.push("all")	
		lg.setCanvas({ canvas_color, canvas_normal, depthstencil=canvas_depth })
		lg.clear(true, true, true)

		lg.setBlendMode("replace") -- NO BLENDING ALLOWED IN MY GAME.

--		lg.setShader(assets.shader_sky)
--		lg.setColor(1, 1, 1, 1)
--
--		local t = vector.from_array(uniforms.view:multiply_vec4({0, 0, 0, 0}))
--		local m = uniforms.projection * uniforms.view * mat4.from_translation(-t)
--		assets.shader_sky:send("inverse_view_proj", "column", m:inverse():to_columns())
--
--		local sun_rot = uniforms.time*0.1
--		local sun = vector(0, -math.sin(sun_rot), math.cos(sun_rot))
--		assets.shader_sky:send("u_sun_params", {sun.x, sun.y, sun.z, 0})
--
--		lg.rectangle("fill", -1, -1, 2, 2)

		lg.setColor(fam.hex "#7e75ff")
		lg.rectangle("fill", 0, 0, w, h)

		lg.setShader(assets.shader)

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
						lg.setCanvas(canvas_flat)
						lg.clear(0, 0, 0, 0)
						lg.setColor(1, 1, 1, 1)
						call:texture()
					lg.pop()

					call.mesh:setTexture(canvas_flat)

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

			lg.setCanvas({ canvas_color, canvas_normal, depthstencil = canvas_depth})
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

        ----------------------------------------------

		table.sort(render_list, function(a, b)
			return a.order > b.order
		end)

		for index, call in ipairs(render_list) do
			render(call)

            render_list[index] = nil
		end

        ----------------------------------------------

		table.sort(grab_list, function(a, b)
			return a.order < b.order
		end)

		for index, call in ipairs(grab_list) do
			render(call)

            grab_list[index] = nil
		end
	lg.pop()

    return vertices
end

local function draw(w, h, state)
    if state.settings.debug then
        state:debug("")
        state:debug("--- RENDERER -----")
        state:debug("CALLS:  %i", #render_list)
        state:debug("GRABS:  %i", #grab_list)
        state:debug("LIGHTS: %i/%i", #light_list, 16)
    end

    do -- Lighting code
		uniforms.ambient = fam.hex "#2c2683"
		uniforms.light_positions = { unpack = true }
		uniforms.light_colors = { unpack = true }
		uniforms.light_amount = #light_list

		for index, light in ipairs(light_list) do
			local pos = light.position:to_array()
			pos.w = 1
			table.insert(uniforms.light_positions, pos)
			table.insert(uniforms.light_colors, light.color)

            light_list[index] = nil
		end

		if uniforms.light_amount == 0 then
			uniforms.light_positions = nil
			uniforms.light_colors = nil
		end
	end

    render_scene(w, h)
end

local function output()
    return canvas_color, canvas_normal, canvas_depth
end

return {
    draw = draw,
    render = render,
    light = light,
    output = output,
    resize = resize,

    uniforms = uniforms,
}