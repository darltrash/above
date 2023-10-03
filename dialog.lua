local input  = require "input"
local fam    = require "fam"
local utf8   = require "utf8"
local ui     = require "ui"
local assets = require "assets"

local dialog = {}
dialog.text = ""
dialog.speed = 1
dialog.selected = 1
dialog.selected_lerp = 1
dialog.options = {}
dialog.options_lerp = 0
dialog.use_options = false
dialog.length = 0

dialog.say = function(self, text, speed, silent, center)
    self.text = text
    self.length = 0
    self.busy = true
    self.silent = silent
    self.speed = speed or 1
    self.use_options = false
    self.center = center
    while self.busy do
        coroutine.yield()
    end
end

dialog.display = function (self, text, speed)
    self:say(text, speed, false, true)
end

dialog.ask = function (self, text, options, speed, silent)
    self.text = text
    self.length = 0
    self.busy = true
    self.silent = silent
    self.speed = speed or 1
    if self.use_options then
       self.options_lerp = 0
    end
    self.use_options = true
    self.options = options
    self.selected = 1
    while self.busy do
        coroutine.yield()
    end

    return self.selected
end

local a = 1
local k = 0
local ready
dialog.on_tick = function (self, dt)
    local speed = 1
    if k ~= math.floor(self.length) then
        local c = self.text:sub(k, k)
        local is_letter = c:match("%a")

        if is_letter then
            assets.sfx_speech:stop()
            assets.sfx_speech:setPitch(1.0)
            assets.sfx_speech:play()
            speed = 1
        elseif c == "*" then
            assets.sfx_speech:stop()
            assets.sfx_speech:setPitch(1 + (1/8))
            assets.sfx_speech:play()
            speed = 5
        end
    end

    k = math.floor(self.length)
    if a < 0.1 then
        self.length = math.min(self.length + dt * 18 * speed * self.speed, #self.text)
    end

    ready = math.floor(self.length) == #self.text
    if ready and input.just_pressed("action") and self.busy then
        if not self.silent then
            assets.sfx_done:play()
        end
        self.busy = false
    end

    local k = dialog.use_options and ready
    if k then
        if input.just_pressed("up") then
            dialog.selected = dialog.selected - 1
            if dialog.selected == 0 then
                dialog.selected = #dialog.options
            end

            assets.sfx_done:play()
        end

        if input.just_pressed("down") then
            dialog.selected = dialog.selected + 1
            if dialog.selected > #dialog.options then
                dialog.selected = 1
            end

            assets.sfx_done:play()
        end
    end
end

dialog.update = function (self, dt)
    local k = dialog.use_options and ready
    local n = k and 1 or 0

    a = fam.decay(a, self.busy and 0 or 1, 2, dt)

    dialog.options_lerp = fam.lerp(dialog.options_lerp, n, 8 * dt)
    if dialog.options_lerp > 0.99 then
        dialog.options_lerp = 1
    end

    dialog.selected_lerp = fam.lerp(dialog.selected_lerp, dialog.selected, 32 * dt)
end

local W, H = 300, 300

local function sub(s,i,j)
    i=utf8.offset(s,i)
    j=utf8.offset(s,j+1) or (#s+1)
    return string.sub(s,i,j-1)
end

--local batch = lg.newSpriteBatch(fn)

-- i wrote this while listening to this:
-- https://www.youtube.com/watch?v=bFZPbqGYCKY

dialog.draw = function(self)
    lg.push("all")
        if a < 0.999 then
            lg.setShader(assets.shd_bwapbwap)
            
            lg.setColor(fam.hex("#18002e", 1-(a*1.3)))
            lg.rectangle("fill", -90, 20+(a*70), 180, 70-(a*70), 9*(1-a), 9*(1-a), 3)

            lg.stencil(function ()
                lg.rectangle("fill", -90, 20+(a*70), 180, 70-(a*70), 9, 9, 3)
            end)
            lg.setStencilTest("greater", 0)

            local message = sub(dialog.text, 1, self.length)
            lg.setColor(1, 1, 1, 1)
            lg.polygon("fill", {
                80-4, 80-4,
                80+4, 80-4,
                80+0, 80+4
            })

            lg.translate(-80, 30)

            local c = 1/7

            local x, y = 5, 0
            if dialog.center then
                c = 1/6
                local w, h = ui.text_length(assets.fnt_atkinson, dialog.text, c)

                x = (160/2)-(w/2)
                y = (50/2)-(h*0.5)
            end

            ui.draw_text(assets.fnt_atkinson, message, x, y, c)
            --lg.rectangle("fill", 0, 0, 160, 50)

        end
    lg.pop()
end

return dialog