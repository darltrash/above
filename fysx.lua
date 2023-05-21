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

world.new = function (grid_size)
    return setmetatable(
        {
            meshes = {},

            grid_size = grid_size,
            hash = {},
        }, world
    )
end

-- Expects table of tables, like {{x=X, y=Y, z=Z}, ...}
--                            or {{X, Y, Z}, ...} in that order
world.add_triangles = function (self, triangles, name)
    local mesh = self.meshes[name] or {}
    if name then
        self.meshes[name] = mesh
    end

    for _, triangle in ipairs(triangles) do
        
    end
end

world.get_triangles = function (self, name)
    return assert(self.meshes[name], 
        "Mesh '"..name.."' does not exist in the world!")
end

world.del_triangles = function (self, name)
    local mesh = self:get_triangles(name)
    
    --for _, triangle in ipairs(s)

    self.meshes[name] = nil
end

return setmetatable(world, {
    __call = function (self, ...)
        return world.new(...)
    end
})