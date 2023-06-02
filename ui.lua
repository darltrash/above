local assets = require "assets"
local dialog = require "dialog"
local fam    = require "fam"
local input  = require "input"
local language = require "language"

math.randomseed(os.time())

local ui = {
    done = false
}

local canvas = lg.newCanvas(300, 300)

local x, y = 0, 0
local real_x, real_y = 0, 0
local mode = false
local selection = 0
local dired = false
local alpha = 0
local scale = 0

ui.update = function (self, dt)
    dialog:update(dt)

    local dir = input.get_direction()
    if math.abs(dir.y) > 0.2 and mode~="intro" and not ui.done then
        if not dired then
            dired = true

            selection = (selection + fam.sign(dir.y)) % 3
            alpha = 1/6
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

    real_x = fam.lerp(real_x, x, dt*3)
    real_y = fam.lerp(real_y, y, dt*3)

    alpha = fam.lerp(alpha, 1.2, dt*5)
end

local function print_center(text, x, y, font, r, s)
    font = font or assets.fnt_main

    lg.setFont(font)
    local ox = font:getWidth(text)/2
    local oy = font:getHeight()/2
    lg.print(text, x, y, r or 0, s, s, ox, oy)
end

local function box(text, x, y, w, h)
    lg.rectangle("fill", x, y, w, h, 3)
    local original = {lg.getColor()}
    lg.setColor(1, 1, 1, 1)
    lg.rectangle("line", x+5, y+5, w-10, h-10)
    print_center(text, x+w/2, (y+h/2)-2)
    lg.setColor(original)
end

ui.draw = function (self, w, h)
    lg.push("all")
        lg.reset()
        lg.setBlendMode("replace")
        lg.setShader(assets.shd_2d)
        lg.setFont(assets.fnt_main)
        lg.setLineStyle("rough")

        lg.setCanvas(canvas)
        lg.clear(0, 0, 0, 0)

        dialog:draw()

        --lg.setColor(1, 1, 1, 1/4)
        --lg.rectangle("line", 1, 1, 299, 299)

        if not ui.done then
            lg.translate(math.floor(-real_x*300), math.floor(-real_y*300))

            lg.setColor(fam.hex"#4e0097")
            lg.rectangle("fill", 150-30, 150-30, 60, 60)

            local r = math.sin(lt.getTime()*1.3)*0.1
            lg.setColor(fam.hex"#ffffff")
            print_center("flowerlove", 150, 147+(r*3), assets.fnt_title, r, 0.5)
            print_center(language.UI_PRESS_ANY_KEY, 150, 240)

            -- SAVES
            print_center(language.UI_SAVE_SELECT, 150, 360)

            for i=0, 2 do
                local a = (i == selection) and alpha or (1/6)
                lg.setColor(fam.hex("#4e0097", a))
                box(language.UI_SAVE_NEW_FILE, 40-(a*2), 390+(45*i)-(a*2), 220+(a*4), 40+(a*4))
            end
        end
    lg.pop()

    local scale = math.floor(math.min(w, h)/300)
    lg.draw(canvas, w/2, h/2, 0.01, scale, scale, 150, 150)
end

return ui