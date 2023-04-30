-- Some sort of map re-encoder.

local ffi = require "ffi"

ffi.cdef[[
    struct header {
        uint32_t size;
    };

    struct vertex {
        float x, y, z, u, v, nx, ny, nz;
    };
]]

if not pcall(debug.getlocal, 4, 1) then    
    local obj = require "lib.obj"

    local file = obj.load(assert(arg[1], "EXPECTED OBJ FILE."))
    local output = io.open(assert(arg[2], "EXPECTED OUTPUT FILE."), "w+b")
    assert(output, "FILE COULD NOT BE CREATED, SOMEHOW?")

    local i = ffi.new("struct header", {#file.vertices})
    local out = ffi.string(i, ffi.sizeof(i))

    -- // TODO: IMPLEMENT INDEXING //////////////////////
    for _, vertex in ipairs(file.vertices) do
        local v = ffi.new("struct vertex", vertex)
        out = out .. ffi.string(v, ffi.sizeof(v))
    end

    output:write(out)
    output:close()

else
    return function (file)
        local model = {
            vertices = {}
        }

        local data = love.filesystem.read(file)

        local header = ffi.new("struct header")
        local length = assert(ffi.sizeof(header))
        ffi.copy(header, data, length)
        data = data:sub(length+1)

        local vertex = ffi.new("struct vertex")
        local length = assert(ffi.sizeof(vertex))

        for x=1, header.size do
            ffi.copy(vertex, data, length)

            table.insert(model.vertices, {
                vertex.x, vertex.y, vertex.z,
                vertex.u, vertex.v,
                vertex.nx, vertex.ny, vertex.nz
            })

            data = data:sub(length+1)
        end

        local format = {
            {"VertexPosition", "float", 3},
            {"VertexTexCoord", "float", 2},
            {"VertexNormal",   "float", 3},
        }

        model.mesh = love.graphics.newMesh(format, model.vertices, "triangles")

        return model
    end

end