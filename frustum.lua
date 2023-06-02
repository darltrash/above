-- NEW TECH ON THE WAY

-- frustum.lua: A simple frustum* library

--[[
    Copyright (c) 2022 Nelson Lopez
    
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

local frustum = {
    left = {0, 0, 0, 0},
    right = {0, 0, 0, 0},
    top = {0, 0, 0, 0},
    bottom = {0, 0, 0, 0},
    near = {0, 0, 0, 0}
}
frustum.__index = frustum
frustum.__type = "frustum"

local function is_frustum(a)
    return getmetatable(a) == frustum
end

frustum.new = function (x, y, z)
    return setmetatable(
        { x = x, y = y, z = z }, frustum
    )
end

frustum.copy = function (self)
    return frustum.new(self.x, self.y, self.z)
end


frustum.is_frustum = is_frustum

return setmetatable(frustum, {
    __call = function (self, ...)
        return frustum.new(...)
    end
})