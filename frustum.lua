-- frustum.lua: A simple frustum* library

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

local frustum = {}
frustum.__index = frustum
frustum.__type = "frustum"

local function is_frustum(a)
    return getmetatable(a) == frustum
end

frustum.is_frustum = is_frustum

frustum.new = function(a)
    return setmetatable(a or {}, frustum)
end

frustum.from_mat4 = function(a, infinite)
    local b = frustum.new()

    local function h(a)
        local t = math.sqrt(a.a * a.a + a.b * a.b + a.c * a.c)
        a.a = a.a / t
        a.b = a.b / t
        a.c = a.c / t
        a.d = a.d / t
        return a
    end

    b.left = h {
        a = a[4]  + a[1],
        b = a[8]  + a[5],
        c = a[12] + a[9],
        d = a[16] + a[13]
    }

    b.right = h {
        a = a[4]  - a[1],
        b = a[8]  - a[5],
        c = a[12] - a[9],
        d = a[16] - a[13]
    }

    b.bottom = h {
        a = a[4]  + a[2],
        b = a[8]  + a[6],
        c = a[12] + a[10],
        d = a[16] + a[14]
    }

    b.top = h {
        a = a[4]  - a[2],
        b = a[8]  - a[6],
        c = a[12] - a[10],
        d = a[16] - a[14]
    }

    b.near = h {
        a = a[4]  + a[3],
        b = a[8]  + a[7],
        c = a[12] + a[11],
        d = a[16] + a[15]
    }

    if not infinite then
        b.far = h {
            a = a[4]  - a[3],
            b = a[8]  - a[7],
            c = a[12] - a[11],
            d = a[16] - a[15]
        }
    end

    return b
end

local function vector(vec)
    return
        vec.x or vec[1],
        vec.y or vec[2],
        vec.z or vec[3]
end

frustum.vs_point = function(self, vec)
    local x, y, z = vector(vec)

    local planes  = {
        frustum.left,
        frustum.right,
        frustum.bottom,
        frustum.top,
        frustum.near,
        frustum.far
    }

    if not planes[6] then
        planes[#planes] = nil
    end

    local dot
    for i = 1, #planes do
        dot =
            planes[i].a * x +
            planes[i].b * y +
            planes[i].c * z +
            planes[i].d

        if dot <= 0 then
            return false
        end
    end

    return true
end

frustum.vs_aabb = function(self, min, max)
    local box = {
        { vector(min) },
        { vector(max) }
    }

    local m = function(a, b)
        if (a > b) then
            return b, a
        end

        return a, b
    end

    -- Ensure min-max is respected, THE AABB SHALL BE RESPECTED.
    box[1][1], box[2][1] = m(box[1][1], box[2][1])
    box[1][2], box[2][2] = m(box[1][2], box[2][2])
    box[1][3], box[2][3] = m(box[1][3], box[2][3])

    local planes = {
        self.left,
        self.right,
        self.bottom,
        self.top,
        self.near,
        self.far
    }

    if not planes[6] then
        planes[#planes] = nil
    end

    for i = 1, #planes do
        local p = planes[i]

        local px = p.a > 0.0 and 2 or 1
        local py = p.b > 0.0 and 2 or 1
        local pz = p.c > 0.0 and 2 or 1

        local dot =
            p.a * box[px][1] +
            p.b * box[py][2] +
            p.c * box[pz][3]

        if dot < -p.d then
            return false
        end
    end

    return true
end

frustum.vs_sphere = function(self, position, radius)
    local x, y, z = vector(position)
    local planes  = {
        self.left,
        self.right,
        self.bottom,
        self.top,
        self.far or self.near
    }

    local dot
    for i = 1, #planes do
        dot =
            planes[i].a * x +
            planes[i].b * y +
            planes[i].c * z +
            planes[i].d

        if dot <= -radius then
            return false
        end
    end

    return dot + radius
end

return setmetatable(frustum, {
    __call = function(self, ...)
        return frustum.new(...)
    end
})
