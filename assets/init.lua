local exm = require "lib.iqm"
local iqm = require "lib.log"
local log = require "lib.log"

-- Here comes the 
--                disgusting hack!

local loaders = {
    mod = function (what)
        -- WHOOPS! might as well change this later on... :)
        -- Edit: The later on has come, it is here.
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
        return lg.newImage("assets/tex/"..what..".png")
    end
}

local ret = setmetatable({
    fnt_main = lg.newFont("assets/fnt_monogram.ttf", 16)

}, {
    __index = function (self, index)
        self[index] = loaders[index:sub(1, 3)](index:sub(5))
        log.info("'%s' loaded and cached!", index)
        return self[index]
    end
})

return ret