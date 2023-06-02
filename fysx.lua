-- fysx.lua: A simple 3D collision resolution engine

-- NOTE: THIS ONLY SUPPORTS SPHERE-TO-TRIANGLE COLLISION RESOLUTION
--       IT ALSO DOES NOT UNDERSTAND ANY REALISTIC PHYSICS CONCEPTS
--       IT'S ESSENTIALLY JUST A FRAMEWORK FOR A PHYSICS ENGINE

--[[
    Copyright (c) 2023 Nelson Lopez
    
    This software is provided 'as-is', without any express or implied warranty. 
    In no event will the authors be held liable for any damages arising from the use of this software.
    
    Permission is granted to anyone to use this software for any purpose, 
    including commercial applications, and to alter it and redistribute it freely, 
    subject to the following restrictions:

    1. The origin of this software must not be misrepresented; 
        you must not claim that you wrote the original software. 
        If you use this software in a product, an acknowledgment 
        in the product documentation would be appreciated but is not required.

    2. Altered source versions must be plainly marked as such, 
        and must not be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
]]

local world = { }
world.__index = world
world.__type = "fysx.world"

local vector = require "lib.vec3"

local floor = math.floor
local ceil = math.ceil
local sqrt = math.sqrt

-- Enough for most games theoretically
local function index(x, y, z) -- 16 bits per axis
    local bx = bit.lshift(floor(x+32767), 0)
    local by = bit.lshift(floor(y+32767), 16)
    local bz = bit.lshift(floor(z+32767), 32)
    return bit.bor(bx, bit.bor(by, bz))
end

local function triangle_aabb(t)
    return 
        math.min(t[1].x, t[2].x, t[3].x),
        math.min(t[1].y, t[2].y, t[3].y),
        math.min(t[1].z, t[2].z, t[3].z),
      
        math.max(t[1].x, t[2].x, t[3].x),
        math.max(t[1].y, t[2].y, t[3].y),
        math.max(t[1].z, t[2].z, t[3].z)
end

local function vec(a)
    return {
        x = a.x or a[1],
        y = a.y or a[2],
        z = a.z or a[3]
    }
end

local function signed_distance(plane, origin)
    return origin:dot(plane.normal) + plane.normal:dot(plane.position)
end

local function closest_point(triangle, origin)
    local va, vb, vc = triangle[1], triangle[2], triangle[3]
  
    local vec_a = origin - va
    local vec_b = origin - vb
    local vec_c = origin - vc
  
    local normal = (vb - va):cross(vc - va)
  
    vec_a = vec_a - (normal * vec_a:dot(normal))
    vec_b = vec_b - (normal * vec_b:dot(normal))
    vec_c = vec_c - (normal * vec_c:dot(normal))
  
    local total_area = normal:dot((vb - va):cross(vc - va))
    local area_a     = normal:dot(vec_b:cross(vec_c)) / total_area
    local area_b     = normal:dot(vec_c:cross(vec_a)) / total_area
    local area_c     = 1 - area_a - area_b
  
    local closest_point

    if area_a >= 0 and area_b >= 0 and area_c >= 0 then
        closest_point = (va * area_a) + (vb * area_b) + (vc * area_c)

    else
        local closest_vertex
        local min_distance = math.huge
    
        local vertices = { va, vb, vc }
        for _, vertex in ipairs(vertices) do
            local distance = (origin - vertex):dot(origin - vertex)
            if distance < min_distance then
                min_distance = distance
                closest_vertex = vertex
            end
        end
    
        closest_point = closest_vertex
    end
    
    return closest_point
end

local function check_triangle(packet, triangle)
    local p1, p2, p3 = triangle[1], triangle[2], triangle[3]
    local normal = (p2 - p1):cross(p3 - p1):normalize()

    local t0 = 0
    local embedded_in_plane = false

    local signed_dist_to_plane = packet.origin:dot(normal) - normal:dot(p1)
    local normal_dot_vel = normal:dot(packet.towards * packet.velocity)

    if (normal_dot_vel == 0) then
        if math.abs(signed_dist_to_plane) >= 1.0 then
            return packet
        end

        embedded_in_plane = true
        t0 = 0

    else
        local nvi = 1 / normal_dot_vel
        t0 = (-1 - signed_dist_to_plane) * nvi
        local t1 = (1.0 - signed_dist_to_plane) * nvi

        if t0 > t1 then
            local t_ = t1
            t1 = t0
            t0 = t_
        end

        if t0 > 1 or t1 < 0 then
            return packet
        end

        t0 = math.max(0, math.min(1, t0))
    end

    local collision_point = vector(0, 0, 0)
    local collision_found = false
    local t = 1

    local velocity = packet.towards * packet.velocity

    if not embedded_in_plane then
        local temp = velocity * t0
        local plane_intersect = (packet.origin - normal) + temp
        
        if triangle_intersects_point(plane_intersect, triangle) then
            collision_found = true
            t = t0
            collision_point = plane_intersect
        end
    end

    if not collision_found then
        local velocity_sq_length = velocity:magnitude_squared()
        local a = velocity_sq_length
        local new_t = { v = 0 }

        local function check_point(collision_point, p)
            local b = 2 * velocity:dot(packet.origin - p)
            local c = (p - packet.origin):magnitude_squared() - 1

            if get_lowest_root(new_t, a, b, c, t) then
                t = new_t.v
                collision_found = true
                collision_point = p
            end

            return collision_point
        end

        collision_point = check_point(collision_point, p1)

        if not collision_found then
            collision_point = check_point(collision_point, p2)
        end

        if not collision_found then
            collision_point = check_point(collision_point, p3)
        end

        local function check_edge(collision_point, pa, pb)
			local edge = pb - pa
			local base_to_vertex = pa - packet.origin
			local edge_sq_length = edge:magnitude_squared()
			local edge_dot_velocity = edge:dot(velocity)
			local edge_dot_base_to_vertex = edge:dot(base_to_vertex)

            local a = edge_sq_length * -velocity_sq_length + edge_dot_velocity * edge_dot_velocity
			local b = edge_sq_length * (2.0 * velocity:dot(base_to_vertex)) - 2.0 * edge_dot_velocity * edge_dot_base_to_vertex
			local c = edge_sq_length * (1.0 - base_to_vertex:magnitude_squared()) + edge_dot_base_to_vertex * edge_dot_base_to_vertex

            if (get_lowest_root(new_t, a, b, c, t)) then
				local f = (edge_dot_velocity * new_t.v - edge_dot_base_to_vertex) / edge_sq_length
				
                if (f >= 0.0 and f <= 1.0) then
					t = new_t.v;
					collision_found = true;
					collision_point = pa + (edge * f)
                end
			end

            return collision_point
        end

		collision_point = check_edge(collision_point, p1, p2)
		collision_point = check_edge(collision_point, p2, p3)
		collision_point = check_edge(collision_point, p3, p1)
    end

    if collision_found then
        local dist_to_coll = t * packet.velocity

        if (not packet.found_collision) or dist_to_coll < packet.nearest_distance then
            packet.nearest_distance = dist_to_coll
			packet.intersect_point  = collision_point
			packet.intersect_time   = t
			packet.found_collision  = true
        end
    end
end

local function check_collision(packet, triangle, ids)
    local inv_radius = 1 / packet.radius
    for i=1, 3 do
        
    end
end

-- This re-implements the improvements to Kasper Fauerby's "Improved Collision
-- detection and Response" proposed by Jeff Linahan's "Improving the Numerical
-- Robustness of Sphere Swept Collision Detection"

-- Originally by github.com/shakesoda!
local VERY_CLOSE_DIST = 0.00125
local function collide_with_world(packet, position, velocity, triangle, ids)
    local first_plane

    position = vector.from_table(position)
    velocity = vector.from_table(velocity)
    local dest = position + velocity
    local speed = 1

    for i=1, 3 do
        packet.towards = velocity:normalize()
        packet.velocity = velocity:magnitude()
        packet.origin = position:copy()
        packet.found_collision = false
        packet.nearest_distance = 1e20

        check_collision(packet, triangle, ids)

        if not packet.found_collision then
            return dest
        end

        local touch_point = position + (velocity * packet.intersect_time)

        local pn = (touch_point - packet.intersect_point):normalize()
        local plane = {
            position = packet.intersect_point,
            normal = pn
        }
        local n = (plane.normal / packet.radius)
        local dist = velocity:magnitude() * packet.intersect_time
        local short_dist = math.max(dist - speed * VERY_CLOSE_DIST, 0.0)

        local nvel = velocity:normalize()
        position = position:add(nvel * short_dist)

        table.insert(packet.contacts, {
            id = packet.id,
            plane = {
                position = plane.position * packet.radius,
                normal = n
            }
        })

        if (i == 1) then
            local long_radius = 1.0 + speed * VERY_CLOSE_DIST
            first_plane = plane

            dest = dest - (first_plane.normal * (signed_distance(first_plane, dest) - long_radius))
            velocity = dest - position

        elseif (i == 2 and first_plane) then
            local second_plane = plane
            local crease = first_plane.normal:cross(second_plane.normal):normalize()
            local dis = (dest - position):dot(crease)
            velocity = crease * dis
            dest = position + velocity

        end
    end

    return position
end

local function resolve(position, velocity, radius)
    local packet = {}


end

local function remove(list, what) -- performs a swap
    for index, element in ipairs(list) do
        if element == what then
            list[index] = list[#list]
            list[#list] = nil
            break
        end
    end
end

world.new = function (grid_size)
    return setmetatable(
        {
            meshes = {},

            grid_size = grid_size or 5,
            hash = {},
        }, world
    )
end

-- inclusive: creates a chunk if it does not exist yet
world.query = function (self, x, y, z, w, h, d, inclusive)
    local sx = floor(x / self.grid_size)
    local sy = floor(y / self.grid_size)
    local sz = floor(z / self.grid_size)

    local ex = ceil((x + w) / self.grid_size)
    local ey = ceil((y + h) / self.grid_size)
    local ez = ceil((z + d) / self.grid_size)

    local routine = coroutine.create(function()
        -- HORRIBLE COMPLEXITY
        for x=sx, ex do
            for y=sy, ey do
                for z=sz, ez do
                    local i = index(x, y, z)
                    local a = self.hash[i]

                    if inclusive then
                        a = {}
                        self.hash[i] = a
                    end

                    if a then
                        coroutine.yield(a, x, y, z, i)
                    end
                end
            end
        end
    end)

    return function ()
        local ok, list, x, y, z, i = coroutine.resume(routine)
        if ok then
            return list, x, y, z, i
        end
    end
end

-- Expects table of tables, like {{x=X, y=Y, z=Z}, ...}
--                            or {{X, Y, Z}, ...} in that order
world.add_triangles = function (self, triangles, name)
    local mesh = self.meshes[name] or {}
    if name then
        self.meshes[name] = mesh
    end

    -- this all looks insanely slow :(
    for _, triangle in ipairs(triangles) do -- Creates a copy of each triangle
        local v1 = vector.from_table(vec(triangle[1]))
        local v2 = vector.from_table(vec(triangle[2]))
        local v3 = vector.from_table(vec(triangle[3]))

        local new_triangle = { v1, v2, v3 }
        new_triangle.aabb = { triangle_aabb(new_triangle) }

        table.insert(mesh, new_triangle)
    end

    for _, triangle in ipairs(mesh) do
        for list in self:query(unpack(triangle.aabb)) do
            table.insert(list, triangle)
        end
    end
end

world.get_mesh = function (self, name)
    return assert(self.meshes[name],
        "Mesh '"..name.."' does not exist in the world!")
end

world.del_triangles = function (self, name)
    local mesh = self:get_triangles(name)
    
    -- the complexity for this garbage is incredible.
    for _, triangle in ipairs(mesh) do
        for list in self:query(unpack(triangle.aabb)) do
            remove(list, triangle)
        end
    end

    self.meshes[name] = nil
end

world.check = function (self, position, velocity, radius)
    local packet = {
        radius = radius,
        contacts = {}
    }
    local position = collide_with_world(packet, position, velocity)
end

return setmetatable(world, {
    __call = function (self, ...)
        return world.new(...)
    end
})