local input  = require "input"
local fam    = require "fam"
local utf8   = require "utf8"
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
        -- HACK
        tx = x + ((w/2) - (assets.fnt_main:getWidth(dialog.text)/2))
        ty = y + ((h/2) - assets.fnt_main:getHeight())
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

--local batch = lg.newSpriteBatch(fn)
local function draw_text(font, text, x, y, scale, length)
	lg.push("all")
		lg.setShader(assets.shd_sdf_font)
		assets.shd_sdf_font:send("thicc", 0.4)
        local sw = false
        local kh = false

		lg.scale(scale)

		local tx = (x/scale)
		local ty = (y/scale) + font.characters["A"].height
		
		for c in text:gmatch(utf8.charpattern) do
			if c == "\n" then
				tx = x / scale
				ty = ty + font.characters["A"].height
			elseif c == "\t" then
				tx = tx + font.characters["A"].width * 4
            elseif c == "*" then
                sw = not sw
                assets.shd_sdf_font:send("thicc", sw and 0.8 or 0.35)
            elseif c == "~" then
                kh = not kh
            else
                local nx = lt.getTime()*0.2
                local ny = (lt.getTime()+0.3)*0.3
				local n = love.math.noise((tx/10)+nx, (ty/10)+ny)
				local t = font.characters[c]
                local r = math.sin((ny*4)+(tx*0.5))*(kh and 4 or 0)
				lg.draw(font.image, t.quad, tx-t.originX, ty-t.originY+r, (n-0.5)/14)
				tx = tx + t.advance
			end
		end
	lg.pop()
end

dialog.draw = function(self)
    k = fam.lerp(k, self.busy and 1 or 0, lt.getDelta()*10)
    if true then return end
    lg.push("all")
        if k < 0.999 then
            lg.setShader(assets.shd_bwapbwap)
            assets.shd_bwapbwap:send("time", lt.getTime())
            lg.setColor(fam.hex"473b78")

            lg.rectangle("fill", -90, 20+(k*70), 180, 70-(k*70), 9, 9, 3)

            lg.stencil(function ()
                lg.rectangle("fill", -90, 20+(k*70), 180, 70-(k*70), 9, 9, 3)
            end)
            lg.setStencilTest("greater", 0)

            local message = "\nThis is but a test of my *nifty powers!*\nMy *SDF TEXT RENDERER* in action!\n\nI'm ~*POWERFUL NOW*~"

            lg.setColor(1, 1, 1, 1)
            lg.polygon("fill", {
                80-4, 80-4,
                80+4, 80-4,
                80+0, 80+4
            })

            lg.setColor(1, 1, 1, 1)
            draw_text(assets.fnt_atkinson, message, -80, 25, 1/7)
        else
            self.busy = false
        end
    lg.pop()
end

return dialog