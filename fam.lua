local fam = {}

fam.lerp = function(a, b, t)
    return a * (1 - t) + b * t
end

fam.decay = function(value, target, rate, delta)
    return fam.lerp(target, value, math.exp(-math.exp(rate) * delta))
end

fam.sign = function(a)
    return (a > 0) and 1 or -1
end

fam.signz = function(a)
    return (a > 0) and 1 or (a < 0) and -1 or 0
end

fam.hex = function(hex, alpha)
    local h = hex:gsub("#", "")
    return {
        (tonumber("0x" .. h:sub(1, 2)) / 255),
        (tonumber("0x" .. h:sub(3, 4)) / 255),
        (tonumber("0x" .. h:sub(5, 6)) / 255),
        alpha or 1
    }
end

fam.split = function(str, sep)
    local t = {}

    for s in str:gmatch("([^" .. (sep or "%s") .. "]+)") do
        table.insert(t, s)
    end

    return t
end

fam.wait = function(ticks)
    local start = lt.getTime()
    while (lt.getTime() - start) < ticks do
        coroutine.yield()
    end
end

fam.animate = function(ticks, callback) -- fn(t)
    local start = lt.getTime()

    local i = 0
    repeat
        i = (lt.getTime() - start) / ticks
        callback(i)
        coroutine.yield()
    until i >= 1
end

fam.clamp = function(x, min, max)
    return x < min and min or (x > max and max or x)
end

fam.aabb = function(x1, y1, w1, h1, x2, y2, w2, h2)
    return x1 < x2 + w2 and
        x2 < x1 + w1 and
        y1 < y2 + h2 and
        y2 < y1 + h1
end

fam.copy_into = function(from, into)
    for k, v in pairs(from) do
        into[k] = v
    end
end

local r = love.math.random
fam.choice = function (array)
    return array[r(1, #array)]
end

local hash3 = {}
hash3.__index = hash3

local function to_cell_key(cx, cy, cz, world_cells)
	cx = math.max(0, math.min(cx, world_cells))
	cy = math.max(0, math.min(cy, world_cells))
	cz = math.max(0, math.min(cz, world_cells))

	return cz * world_cells * world_cells + cy * world_cells + cx
end

hash3.new = function (cell_size)
    cell_size = cell_size or 50

    return setmetatable({
        cell_size = cell_size,
        cells = {},
        oversize = {},
        oversize_threshold = 100,
        world_offset = 1e7 / cell_size / 2,
        world_cells = 1e7;
    }, hash3)
end
hash3.__call = function (self, ...) return hash3.new() end

hash3.refresh = function (self, items, cb)
    self.cells = {}
    self.oversize = {}

    for i = 1, #items do
        local item = items[i]
        local size = cb(item)

        local x = size[1]
        local y = size[2]
        local z = size[3]
        local w = size[4]
        local h = size[5]
        local d = size[6]
        local fcx = (x + self.world_offset) / self.cell_size
        local fcy = (y + self.world_offset) / self.cell_size
        local fcz = (z + self.world_offset) / self.cell_size
        local cr = math.ceil(fcx + w / self.cell_size)
        local cb = math.ceil(fcy + h / self.cell_size)
        local cg = math.ceil(fcz + d / self.cell_size)
        local bcx = math.floor(fcx)
        local bcy = math.floor(fcy)
        local bcz = math.floor(fcz)
        local cw = cr - bcx
        local ch = cb - bcy
        local cd = cg - bcz

        if (cw * ch * cd > self.oversize_threshold) then
            table.insert(self.oversize, item)
            
            goto continue
        end

        for cz = bcz, bcz + cd do
            for cy = bcy, bcy + ch do
                for cx = bcx, bcx + cw do
                    local key = to_cell_key(cx, cy, cz, self.world_cells)
                    local cell = self.cells[key]

                    if not cell then
                        cell = {}
                        self.cells[key] = cell
                    end

                    table.insert(cell, item)
                end
            end
        end

        ::continue::
    end
end

hash3.query_cube = function (self, x, y, z, w, h, d, hit)
    local list
    if not hit then
        list = {}

        hit = function (a)
            table.insert(list, a)
        end
    end

    local fcx = (x + self.world_offset) / self.cell_size
    local fcy = (y + self.world_offset) / self.cell_size
    local fcz = (z + self.world_offset) / self.cell_size
    local cr = math.ceil(fcx + w / self.cell_size)
    local cb = math.ceil(fcy + h / self.cell_size)
    local cg = math.ceil(fcz + d / self.cell_size)
    local bcx = math.floor(fcx)
    local bcy = math.floor(fcy)
    local bcz = math.floor(fcz)
    local cw = cr - bcx
    local ch = cb - bcy
    local cd = cg - bcz

    for _, v in ipairs(self.oversize) do
        hit(v)
    end

    for cz = bcz, bcz + cd do
        for cy = bcy, bcy + ch do
            for cx = bcx, bcx + cw do
                local key = to_cell_key(cx, cy, cz, self.world_cells)
                local cell = self.cells[key]

                if cell then
                    for _, v in ipairs(cell) do
                        hit(v)
                    end
                end
            end
        end
    end

    return list
end

fam.hash3 = hash3

return fam
