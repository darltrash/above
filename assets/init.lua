local exm = require "lib.iqm"
local iqm = require "lib.log"

-- Here comes the 
--                disgusting hack!

local loaders = {
    mod = function (what)
        -- WHOOPS! might as well change this later on... :)
        return exm.load("assets/mod/"..what..".exm", true).mesh
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
        iqm.info("%s, %s", index:sub(1, 3), index:sub(5))
        self[index] = loaders[index:sub(1, 3)](index:sub(5))
        return self[index]
    end
})

return ret