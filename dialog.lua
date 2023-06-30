local input  = require "input"
local fam    = require "fam"
local utf8   = require "utf8"
local assets = require "assets"

-- TODO: fix centering
-- TODO: make the arrow point to the currently selected element

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
    self.length = math.min(self.length + dt * 18 * speed * self.speed, #self.text)

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

    a = fam.decay(a, self.busy and 0 or 1, 1.5, dt)

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

local function printw(text, x, y, w, h, color, highlight, center)
    local tx = x
    local ty = y

    if center then
        tx = x + ((w/2) - (assets.fnt_main:getWidth(text:gsub('[%*%^]', ''))/2))
        ty = y + ((h/2) - (assets.fnt_main:getHeight()/2))
    end

    local ox = tx
    local oy = ty
    local sw = false
    local sh = false

    for char in text:gmatch(utf8.charpattern) do
        if char == "~" then
            sw = not sw
        elseif char == "^" then
            sh = not sh
        elseif char == "\n" then
            tx = ox
            ty = ty + assets.fnt_main:getHeight()
        elseif string.byte(char) < 32 then
        else
            lg.setColor(sh and highlight or color)
            local i = sw and math.sin((lt.getTime() * 5) + tx) or 0
            lg.print(char, tx, ty+i)
            tx = tx + assets.fnt_main:getWidth(char)
        end
    end
end

dialog.draw = function(self)
    lg.push("all")
        lg.translate(0, (a * a) * (H / 2))

        local y = H * 0.7
        local m = 4
        local mm = 4
        
        local n = (1.1-a) ^ 2

        local DARK = fam.hex("#0d0025", n)
        lg.setColor(DARK)
        lg.rectangle("fill", 1+m, y+m, (W-2)-(m*2), (H-y)-1-(m*2), 5)

        local tx = 8+m+mm
        local ty = y+m+mm+5

        local LIGHT = fam.hex("#dadada", n)
        local HIGHLIGHT = fam.hex("#bc81ff", n)
        lg.setColor(LIGHT)

        if ready and (math.floor((lt.getTime() * 2)%2)==0) then
            lg.circle("fill", W-m-mm-10, y+((H-y)-1-2-(mm*3))-2, 4, 3) -- i'm using a circle as a triangle (ho)
        end

        printw(
            sub(self.text, 1, self.length), tx, ty,
            (W-2)-(m*4)-(mm*3), (H-y)-(m*4)-(mm*2),
            LIGHT, HIGHLIGHT, self.center
        )

        lg.setColor(fam.hex("#0d0025", dialog.options_lerp))
        lg.rectangle("fill", W-100-m, y+m, 100, (H-y)-1-(m*2), 5)

        lg.setColor(fam.hex("#2f1b55", dialog.options_lerp))
        lg.rectangle("fill", W-100-m, y+m+(dialog.selected_lerp*12)+2, 100, 12)

        lg.setColor(fam.hex("#dadada", dialog.options_lerp))
        for i, v in ipairs(dialog.options) do
            lg.print(v, (W-100-m)+8, y+m+(i*12))
        end
    lg.pop()
end

return dialog