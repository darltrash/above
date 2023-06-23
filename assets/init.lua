local exm = require "lib.iqm"
local iqm = require "lib.log"
local log = require "lib.log"

-- Here comes the 
--                disgusting hack!

local loaders = {
    mod = function (what)
        return exm.load("assets/mod/"..what..".exm")
    end,

    mus = function (what)
        return la.newSource("assets/mus/"..what..".mp3", "stream")
    end,

    sfx = function (what)
        return la.newSource("assets/sfx/"..what..".ogg", "static")
    end,

    shd = function (what)
        return lg.newShader("assets/shd/"..what..".glsl")
    end,

    tex = function (what)
        local out = lg.newImage("assets/tex/"..what..".png")
        out:setWrap("repeat", "repeat")
        out:setFilter("nearest", "nearest")
        return out
    end
}

local loaded = 1
local ret = setmetatable({
    fnt_main = lg.newFont("assets/fnt_monogram.ttf", 16)

}, {
    __index = function (self, index)
        self[index] = loaders[index:sub(1, 3)](index:sub(5))
        log.info("'%s' loaded and cached!", index)
        loaded = loaded + 1
        return self[index]
    end,

    __len = function (self)
        return loaded
    end
})

return ret