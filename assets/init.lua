local exm = require "lib.iqm"
local log = require "lib.log"
local json = require "lib.json" -- Move this to bitser stuff? Maybe not.

-- Here comes the 
--                disgusting hack!

local template = love.filesystem.read("assets/shk/template.glsl")

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

    shk = function (what)
        local text = love.filesystem.read("assets/shk/"..what..".glsl")
        local g = template:gsub("<template>", text)
        return lg.newShader(g)
    end,

    tex = function (what)
        local out = lg.newImage("assets/tex/"..what..".png")
        out:setWrap("repeat", "repeat")
        out:setFilter("nearest", "nearest")
        return out
    end,

    txd = function (what)
        return love.image.newImageData("assets/tex/"..what..".png")
    end,

    fnt = function (what)
        local text  = love.filesystem.read("assets/fnt/"..what..".json")
        local image = lg.newImage("assets/fnt/"..what..".png")

        local data = json.decode(text)
        data.image = image

        for _, value in pairs(data.characters) do
            value.quad = lg.newQuad(value.x, value.y, value.width, value.height, data.width, data.height)
        end

        return data
    end
}

local emoji = {
    mod = "📐", mus = "🎵", sfx = "🎧",
    shd = "🌈", shk = "✨", tex = "😀",
    fnt = "✒️", txd = "🤯"
}

local loaded = 1
local ret = setmetatable({
    fnt_main = lg.newFont("assets/fnt_monogram.ttf", 16),

}, {
    __index = function (self, index)
        local a = index:sub(1, 3)
        self[index] = loaders[a](index:sub(5))
        log.info("%s '%s' loaded and cached!", emoji[a], index)
        loaded = loaded + 1
        return self[index]
    end,

    __len = function (self)
        return loaded
    end
})

return ret