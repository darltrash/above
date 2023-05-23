local input = require "input"
local fam   = require "fam"
local utf8  = require "utf8"
local assets= require "assets"

local dialog = {}
dialog.text = ""

dialog.say = function(self, text)
    self.text = text
    self.length = 0
    self.busy = true
    while self.busy do
        coroutine.yield()
    end
end

local a = 1
dialog.update = function (self, dt)
    self.length = math.min((self.length or 0) + dt * 18, #self.text)

    local ready = math.floor(self.length) == #self.text
    if ready and input.just_pressed("action") then

        self.busy = false
    end

    a = fam.decay(a, self.busy and 0 or 1, 1.5, dt)
end

local W, H = 300, 300

local function sub(s,i,j)
    i=utf8.offset(s,i)
    j=utf8.offset(s,j+1) or (#s+1)
    return string.sub(s,i,j-1)
end

--printw = (text, x, y, w, c) ->
--	tx = x 
--	ty = y
--	sw = false
--	for word in text\gmatch "%S+"
--		tw = print word, 0, -300, 0
--		if (tx+tw) >= (x+w)
--			tx = x
--			ty += 7
--
--		for char in word\gmatch "."
--			if char == "~"
--			 	sw = not sw
--
--			tx += print char, tx, ty, c
--		tx += 6

local function printw(text, x, y, w, c)
    local tx = x
    local ty = y
    local sw = false

    for char in text:gmatch(utf8.charpattern) do
        if char == "~" then
            sw = not sw
        end

        lg.print(char, tx, ty)
        tx = tx + assets.font:getWidth(char)

        if char == "\n" then
            tx = x
            ty = ty + assets.font:getHeight()
        end
    end

end

dialog.draw = function(self)
    lg.translate(0, (a * a) * (H / 2))

    local y = H * 0.7
    local m = 4
    local mm = 8

    lg.setColor(fam.hex"#dadada")
    lg.rectangle("fill", 1+mm, y+1+mm, W-2-(mm*2),    (H-y)-1-2-(mm*2))
    lg.rectangle("fill", 2+mm, y+mm,  (W-2)-2-(mm*2), (H-y)-1-(mm*2))
    
    local c = fam.hex"#0d0025"
    lg.setColor(c)
    lg.rectangle("fill", 1+m+mm, y+m+mm, (W-2)-(m*2)-(mm*2), (H-y)-1-(m*2)-(mm*2))

    c[4] = 1 / 3
    lg.setColor(c)
    lg.rectangle("fill", 1+m+mm, y+m+mm, (W-2)-(mm*2)-m, (H-y)-1-(mm*2)-m)

    local tx = 8+m+mm
    local ty = y+m+mm+5

    lg.setColor(fam.hex"#dadada")
    printw(sub(self.text, 1, self.length), tx, ty, W-5)
end

return dialog