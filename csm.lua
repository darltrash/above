-- adapted from shake's engine
-- i can't stress this enough, everything shake makes is blursed.

local mat4 = require "lib.mat4"
local vec3 = require "lib.vec3"

local function split_frustum(_num_splits, _near, _far, _split_weight)
	local ratio = _far / _near
	local num_slices = _num_splits * 2

	local splits = { 0, _near }

	local ff = 2
	local nn = 3
	while nn <= num_slices do
		local si = ff / num_slices

		local l = _split_weight
		local nearp = l*(_near*math.pow(ratio, si) ) + (1 - l)*(_near + (_far - _near)*si)
		splits[nn] = nearp -- near
		splits[ff] = nearp * 1.05 -- far from previous split
		ff = ff + 2
		nn = nn + 2
	end

	-- last slice.
	splits[num_slices] = _far

	return splits
end

local function sign(value)
	return value < 0 and -1 or (value > 0 and 1 or 0)
end

local function mul_vec3_persp(a, b)
	local x = b.x * a[1] + b.y * a[5] + b.z * a[9]  + a[13]
	local y = b.x * a[2] + b.y * a[6] + b.z * a[10] + a[14]
	local z = b.x * a[3] + b.y * a[7] + b.z * a[11] + a[15]
	local w = b.x * a[4] + b.y * a[8] + b.z * a[12] + a[16]
	local inv_w = sign(w)/w
	local g = vec3(x*inv_w, y*inv_w, z*inv_w)
	g.w = 1

	return g
end

local function ws_frustum_corners(_proj, _near, _far, _inv_view_mtx)
	-- h=1.0/tan(rad(fovy) * 0.5), w=1.0/(h*aspect). invert them rgba.xback.
	local proj_width = 1.0/_proj[1]
	local proj_height = 1.0/_proj[6]

	-- define frustum corners in view space, convert to world space.
	local nw = _near * proj_width
	local nh = _near * proj_height
	local fw = _far  * proj_width
	local fh = _far  * proj_height

	return {
		mul_vec3_persp(_inv_view_mtx, vec3(-nw,  nh, -_near)),
		mul_vec3_persp(_inv_view_mtx, vec3( nw,  nh, -_near)),
		mul_vec3_persp(_inv_view_mtx, vec3( nw, -nh, -_near)),
		mul_vec3_persp(_inv_view_mtx, vec3(-nw, -nh, -_near)),
		mul_vec3_persp(_inv_view_mtx, vec3(-fw,  fh, -_far )),
		mul_vec3_persp(_inv_view_mtx, vec3( fw,  fh, -_far )),
		mul_vec3_persp(_inv_view_mtx, vec3( fw, -fh, -_far )),
		mul_vec3_persp(_inv_view_mtx, vec3(-fw, -fh, -_far ))
	}
end

local min = vec3(0, 0, 0)
local max = vec3(0, 0, 0)
local mtx_crop = mat4 {
	2, 0, 0, 0,
	0, 2, 0, 0,
	0, 0, 1, 0,
	2, 2, 0, 1
}

-- local -> world -> view -> clip

-- shadow: { split_count: int, distance: int, split_distribution: float, stabilize: bool, res: int }
-- cam: { view: mat4, proj: mat4, world_from_view: mat4 }
local function setup_csm(shadow, light_dir, world_from_view, proj)
	-- local near = (2 * proj[15]) / (2 * proj[11] - 2)
	-- local far = ((proj[11] - 1) * near) / (proj[11] + 1)
	-- setup light view mtx.
	local light_view = mat4.look_at(light_dir, vec3(0, 0, 0), vec3(1, 0, 0))
	local split_slices = split_frustum(
		shadow.split_count,
		0.01,
		shadow.distance,
		shadow.split_distribution
	)
	local depth_range = 250
	local mtx_proj = mat4.from_ortho(-1, 1, -1, 1, -1, depth_range)
	local light_proj = {}
	local num_corners = 8

	for i=1,shadow.split_count do
		local near = split_slices[(i-1)*2+1]
		local far  = split_slices[(i-1)*2+2]

		-- compute frustum corners for one split in world space.
		local frustum_corners = ws_frustum_corners(proj, near, far, world_from_view)

		min = vec3(0, 0, 0)
		max = vec3(0, 0, 0)

		for j=1,num_corners do
			-- transform to light space.
			local a = light_view * frustum_corners[j]
			local ls_frustum_corner = vec3.from_table(a)

			-- update bounding box.
			min = min:min(ls_frustum_corner)
			max = max:max(ls_frustum_corner)
		end

		local minproj = mul_vec3_persp(mtx_proj, min)
		local maxproj = mul_vec3_persp(mtx_proj, max)

		local scalex = 2.0 / (maxproj.x - minproj.x)
		local scaley = 2.0 / (maxproj.y - minproj.y)

		if shadow.stabilize then
			local quantizer = 64.0
			scalex = quantizer / math.ceil(quantizer / scalex)
			scaley = quantizer / math.ceil(quantizer / scaley)
		end

		local offsetx = -0.5 * (maxproj.x + minproj.x) * scalex
		local offsety = -0.5 * (maxproj.y + minproj.y) * scaley

		if shadow.stabilize then
			local half_size = shadow.res * 0.5
			offsetx = math.ceil(offsetx * half_size) / half_size
			offsety = math.ceil(offsety * half_size) / half_size
		end

		mtx_crop[1] = scalex
		mtx_crop[6] = scaley
		mtx_crop[13] = offsetx
		mtx_crop[14] = offsety

		table.insert(light_proj, mtx_crop * mtx_proj * light_view)
	end

	local bias = mat4 {
		0.5, 0.0, 0.0, 0.0,
		0.0, 0.5, 0.0, 0.0,
		0.0, 0.0, 0.5, 0.0,
		0.5, 0.5, 0.5, 1.0
	}
	local shadow_map_mtx = {}
	for i=1,shadow.split_count do
		shadow_map_mtx[i] = bias * light_proj[i]
	end

	return {
		lights = light_proj,
		shadows = shadow_map_mtx
	}
end

return {
	setup_csm = setup_csm
}