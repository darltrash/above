-- Adapted from Shake's engine
-- I can't stress this enough, everything Shake makes is blursed.

local mat4 = require "lib.mat4"
local vec3 = require "lib.vec3"

local function split_frustum(_numSplits, _near, _far, _splitWeight)
	local ratio = _far / _near
	local numSlices = _numSplits * 2

	local splits = { 0, _near }

	local ff = 2
	local nn = 3
	while nn <= numSlices do
		local si = ff / numSlices

		local l = _splitWeight
		local nearp = l*(_near*math.pow(ratio, si) ) + (1 - l)*(_near + (_far - _near)*si)
		splits[nn] = nearp -- near
		splits[ff] = nearp * 1.05 -- far from previous split
		ff = ff + 2
		nn = nn + 2
	end

	-- Last slice.
	splits[numSlices] = _far

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
	local a = vec3(x*inv_w, y*inv_w, z*inv_w)
	a.w = 1
	return a
end

local function ws_frustum_corners(_proj, _near, _far, _invViewMtx)
	-- h=1.0/tan(rad(fovy) * 0.5), w=1.0/(h*aspect). invert them back.
	local projWidth = 1.0/_proj[1]
	local projHeight = 1.0/_proj[6]

	-- Define frustum corners in view space, convert to world space.
	local nw = _near * projWidth
	local nh = _near * projHeight
	local fw = _far  * projWidth
	local fh = _far  * projHeight

	return {
		mul_vec3_persp(_invViewMtx, vec3(-nw,  nh, -_near)),
		mul_vec3_persp(_invViewMtx, vec3( nw,  nh, -_near)),
		mul_vec3_persp(_invViewMtx, vec3( nw, -nh, -_near)),
		mul_vec3_persp(_invViewMtx, vec3(-nw, -nh, -_near)),
		mul_vec3_persp(_invViewMtx, vec3(-fw,  fh, -_far )),
		mul_vec3_persp(_invViewMtx, vec3( fw,  fh, -_far )),
		mul_vec3_persp(_invViewMtx, vec3( fw, -fh, -_far )),
		mul_vec3_persp(_invViewMtx, vec3(-fw, -fh, -_far ))
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

-- shadow: { split_count: int, distance: int, split_distribution: float, stabilize: bool, res: int }
-- cam: { view: mat4, proj: mat4, world_from_view: mat4 }
local function setup_csm(shadow, light_dir, world_from_view, proj)
	local lightView = mat4.look_at(-light_dir, 0, vec3(0, 0, 1))
	local splitSlices = split_frustum(
		shadow.split_count,
		0.01,
		shadow.distance,
		shadow.split_distribution
	)
	local depth_range = 500
	local mtxProj = mat4.from_ortho(-1, 1, -1, 1, -depth_range, depth_range)
	local lightProj = {}
	local numCorners = 8

	for i=1, shadow.split_count do
		local near = splitSlices[(i-1)*2+1]
		local far  = splitSlices[(i-1)*2+2]

		-- Compute frustum corners for one split in world space.
		local frustumCorners = ws_frustum_corners(proj, near, far, world_from_view)

		min = vec3(0, 0, 0)
		max = vec3(0, 0, 0)

		for j=1, numCorners do
			-- Transform to light space.
			local lightSpaceFrustumCorner = vec3.from_table(lightView * frustumCorners[j])

			-- Update bounding box.
			min = min:min(lightSpaceFrustumCorner)
			max = max:max(lightSpaceFrustumCorner)
		end

		local minproj = mul_vec3_persp(mtxProj, min)
		local maxproj = mul_vec3_persp(mtxProj, max)

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
			local halfSize = shadow.res * 0.5
			offsetx = math.ceil(offsetx * halfSize) / halfSize
			offsety = math.ceil(offsety * halfSize) / halfSize
		end

		mtx_crop[1] = scalex
		mtx_crop[6] = scaley
		mtx_crop[13] = offsetx
		mtx_crop[14] = offsety

		table.insert(lightProj, mtx_crop * mtxProj * lightView)
	end

	local bias = mat4 {
		0.5, 0.0, 0.0, 0.0,
		0.0, 0.5, 0.0, 0.0,
		0.0, 0.0, 0.5, 0.0,
		0.5, 0.5, 0.5, 1.0
	}
	local shadowMapMtx = {}
	for i=1,shadow.split_count do
		shadowMapMtx[i] = bias * lightProj[i]
	end

	return {
		lights = lightProj,
		shadows = shadowMapMtx
	}
end

return {
	setup_csm = setup_csm
}

--[[
	export function setup_csm(shadow: ShadowSettings, light_dir: number[], world_from_view: Mat4, proj: Mat4) {
		const near = (2 * proj[14]) / (2 * proj[10] - 2);
		const far = ((proj[10] - 1) * near) / (proj[10] + 1);
		const ldir = vec3(light_dir[0], light_dir[1], light_dir[2]);
		const lightView = cpml.mat4.look_at(cpml.mat4(), ldir, vec3(0, 0, 0), vec3(0, 1, 0));
		let distance = shadow.distance;
		let bmin = vec3();
		let bmax = vec3();
		if (shadow.bounds) {
			bmax = vec3(shadow.bounds.max[0], shadow.bounds.max[1], shadow.bounds.max[2]);
			bmin = vec3(shadow.bounds.min[0], shadow.bounds.min[1], shadow.bounds.min[2]);
			distance = cpml.vec3.len(cpml.vec3.sub(bmax, bmin)) * (1 + shadow.overlap);
		}
		distance = Math.min(far, distance);
		const splitSlices = split_frustum(
			shadow.split_count,
			near,
			distance,
			shadow.split_distribution,
			shadow.overlap ? shadow.overlap : 0.05
		);
		// better solution would be to intersect the bounding box provided
		const depth_range = shadow.depth_range ? shadow.depth_range : distance;
		const mtxProj = mat4.from_ortho(-1, 1, -1, 1, -depth_range, depth_range);
		const vp = cpml.mat4.mul(cpml.mat4(), mtxProj, lightView);
		const lightProj: Mat4[] = [];
		const numCorners = 8;

		for (let i = 0; i < shadow.split_count; i++) {
			const near = splitSlices[i*2];
			const far  = splitSlices[i*2+1];

			// Compute frustum corners for one split in world space.
			const frustumCorners = ws_frustum_corners(proj, near, far, world_from_view);

			// const f4 = cpml.mat4.mul_vec4([0, 0, 0, 1], lightView, [ frustumCorners[0].x, frustumCorners[0].y, frustumCorners[0].z, 1 ]);
			// const first = vec3(f4[0], f4[1], f4[2]);
			const first = mul_vec3_persp(lightView, frustumCorners[0]);
			min = first;
			max = first;

			for (let j = 1; j < numCorners; j++) {
				// Transform to light space.
				const lightSpaceFrustumCorner = mul_vec3_persp(lightView, frustumCorners[j]);

				// Update bounding box.
				min = vec3.component_min(min, lightSpaceFrustumCorner);
				max = vec3.component_max(max, lightSpaceFrustumCorner);
			}

			if (shadow.overlap) {
				min = vec3.sub(min, cpml.vec3(1 + shadow.overlap));
				max = vec3.add(max, cpml.vec3(1 + shadow.overlap));
			}

			// clamp to world bounds if provided
			if (shadow.bounds) {
				min = vec3.component_min(min, bmax);
				max = vec3.component_max(max, bmin);
			}

			const minproj = mul_vec3_persp(mtxProj, min);
			const maxproj = mul_vec3_persp(mtxProj, max);

			let scalex = 2.0 / (maxproj.x - minproj.x);
			let scaley = 2.0 / (maxproj.y - minproj.y);

			if (shadow.stabilize) {
				const quantizer = 64.0;
				scalex = quantizer / Math.ceil(quantizer / scalex);
				scaley = quantizer / Math.ceil(quantizer / scaley);
			}

			let offsetx = -0.5 * (maxproj.x + minproj.x) * scalex;
			let offsety = -0.5 * (maxproj.y + minproj.y) * scaley;

			if (shadow.stabilize) {
				const halfSize = shadow.res * 0.5;
				offsetx = Math.ceil(offsetx * halfSize) / halfSize;
				offsety = Math.ceil(offsety * halfSize) / halfSize;
			}

			mtxCrop[0] = scalex;
			mtxCrop[5] = scaley;
			mtxCrop[12] = offsetx;
			mtxCrop[13] = offsety;

			lightProj.push(mat4.mul(mat4(), mtxCrop, vp));
		}

		return lightProj;
	}
]]
