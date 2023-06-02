local input = require "input"
local fam   = require "fam"
local utf8  = require "utf8"
local assets= require "assets"

local dialog = {}
dialog.text = ""
dialog.speed = 1

dialog.say = function(self, text, speed, silent)
    self.text = text
    self.length = 0
    self.busy = true
    self.silent = silent
    self.speed = speed or 1
    while self.busy do
        coroutine.yield()
    end
end

local a = 1
local k = 0
local ready
dialog.update = function (self, dt)
    self.length = self.length or 0

    local is_letter = self.text:sub(k, k):match("%a")
    if k ~= math.floor(self.length) and is_letter then
        assets.sfx_speech:stop()
        assets.sfx_speech:play()
    end

    k = math.floor(self.length)
    self.length = math.min(self.length + dt * 18 * self.speed, #self.text)

    ready = math.floor(self.length) == #self.text
    if ready and input.just_pressed("action") and self.busy then
        if not self.silent then
            assets.sfx_done:play()
        end
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
        tx = tx + assets.fnt_main:getWidth(char)

        if char == "\n" then
            tx = x
            ty = ty + assets.fnt_main:getHeight()
        end
    end

end

dialog.draw = function(self)
    lg.push("all")
        lg.translate(0, (a * a) * (H / 2))

        local y = H * 0.7
        local m = 4
        local mm = 4
        
        lg.setColor(fam.hex("#0d0025", (1.1-a) ^ 2))
        lg.rectangle("fill", 1+m, y+m, (W-2)-(m*2), (H-y)-1-(m*2), 5)

        local tx = 8+m+mm
        local ty = y+m+mm+5

        lg.setColor(fam.hex("#dadada", (1.1-a) ^ 2))
        if ready and (math.floor((lt.getTime() * 2)%2)==0) then
            lg.circle("fill", W-m-mm-10, y+((H-y)-1-2-(mm*3))-2, 4, 3) -- i'm using a circle as a triangle
        end
        printw(sub(self.text, 1, self.length), tx, ty, W-5)
    lg.pop()
end

return dialog