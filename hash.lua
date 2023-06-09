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

local vector = require "lib.vec3"
local slam = require "lib.slam"

local floor = math.floor
local ceil = math.ceil

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

            grid_size = grid_size or 1,
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

world.query_list = function (self, x, y, z, w, h, d)
    local sx = floor(x / self.grid_size)
    local sy = floor(y / self.grid_size)
    local sz = floor(z / self.grid_size)

    local ex = ceil((x + w) / self.grid_size)
    local ey = ceil((y + h) / self.grid_size)
    local ez = ceil((z + d) / self.grid_size)

    local list = {}

    for x=sx, ex do
        for y=sy, ey do
            for z=sz, ez do
                local a = self.hash[index(x, y, z)]

                if a then
                    for _, v in ipairs(a) do
                        table.insert(list, v)
                    end
                end
            end
        end
    end

    return list
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
        table.insert(mesh, {
            vector.from_table(vec(triangle[1])),
            vector.from_table(vec(triangle[2])),
            vector.from_table(vec(triangle[3]))
        })
    end

    for _, triangle in ipairs(mesh) do
        local x, y, z, w, h, d = triangle_aabb(triangle)
        for list in self:query(x, y, z, w, h, d, true) do
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

local function query(min, max, velocity, world)
    return world:get_mesh("level") --world:query_list(min.x, min.y, min.z, max.x, max.y, max.z)
end

world.check = function (self, position, velocity, radius, substeps)
    return slam.check(position, velocity, radius, query, substeps, self)
end

return setmetatable(world, {
    __call = function (self, ...)
        return world.new(...)
    end
})