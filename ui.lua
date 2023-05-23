local assets = require "assets"
local dialog = require "dialog"

local ui = {}

local canvas = lg.newCanvas(300, 300)

ui.update = function (self, dt)
    dialog:update(dt)
end

ui.draw = function (self, w, h)
    lg.push("all")
        lg.reset()
        lg.setFont(assets.font)
        lg.setLineStyle("rough")

        lg.setCanvas(canvas)
        lg.clear(0, 0, 0, 0)

        dialog:draw()

        --lg.setColor(1, 1, 1, 1/4)
        --lg.rectangle("line", 1, 1, 299, 299)
    lg.pop()

    lg.draw(canvas, (w/2)-150, (h/2)-150, 0.01)
end

return ui