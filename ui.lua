local assets   = require "assets"
local dialog   = require "dialog"
local fam      = require "fam"
local input    = require "input"
local language = require "language"

math.randomseed(os.time())

local ui = {
    done = false
}

local canvas = lg.newCanvas(300, 300)

local x, y = 0, 0
local real_x, real_y = 0, 0
local mode = ""
local selection = 0
local dired = false
local sel_alpha = 0
local alpha = 1
local scale = 0

ui.on_tick = function(self, dt)
    dialog:on_tick(dt)
end

ui.update = function(self, dt)
    dialog:update(dt)

    local dir = input.get_direction()
    if math.abs(dir.y) > 0.2 and mode ~= "intro" and not ui.done then
        if not dired then
            dired = true

            selection = (selection + fam.sign(dir.y)) % 3
            sel_alpha = 1 / 6
            assets.sfx_speech:play()
        end
    else
        dired = false
    end

    if mode == "intro" then
        x = 0
        y = 0
        if input.just_pressed("any") then
            mode = "saves"
            assets.sfx_done:play()
        end
    elseif mode == "saves" then
        x = 0
        y = 1
    elseif mode == "settings" then
        x = 1
        y = 1
    else
        ui.done = true
    end

    real_x = fam.lerp(real_x, x, dt * 3)
    real_y = fam.lerp(real_y, y, dt * 3)

    sel_alpha = fam.lerp(sel_alpha, 1.2, dt * 5)

    alpha = fam.lerp(alpha, ui.done and 0 or 1, dt * 5)
end

local function print_center(text, x, y, font, r, s)
    font = font or assets.fnt_main

    lg.setFont(font)
    local ox = font:getWidth(text) / 2
    local oy = font:getHeight() / 2
    lg.print(text, x, y, r or 0, s, s, ox, oy)
end

local function box(text, x, y, w, h)
    lg.rectangle("fill", x, y, w, h, 3)
    local original = { lg.getColor() }
    lg.setColor(1, 1, 1, 1)
    lg.rectangle("line", x + 5, y + 5, w - 10, h - 10)
    print_center(text, x + w / 2, (y + h / 2) - 2)
    lg.setColor(original)
end

-- TODO: Savefile loading and reading
-- TODO: Settings management

ui.draw = function(self, w, h, state)
    lg.push("all")
        local s = math.max(1, math.min(w, h)/200)
        lg.scale(s)
        lg.translate(w/s/2, h/s/2)
        --lg.rectangle("fill", 10, 10, 30, 30)

        dialog:draw()
    lg.pop()
end

return ui
