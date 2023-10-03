local assets   = require "assets"
local fam      = require "fam"
local input    = require "input"
local language = require "language"
local utf8     = require "utf8"
local vec3     = require "lib.vec3"

math.randomseed(os.time())

local ui = {
    mode = false
}

ui.dark = fam.hex"#18002e"
ui.clear = fam.hex"#f3d4ff"
ui.sky_cycle = assets.txd_sky_gradient

local dialog
ui.load = function ()
    dialog = require "dialog"
end

ui.draw_text = function (font, text, x, y, scale)
	lg.push()
		lg.setShader(assets.shd_sdf_font)
		assets.shd_sdf_font:send("thicc", 0.4)
        local sw = false
        local kh = false

		lg.scale(scale)

		local tx = (x/scale)
		local ty = (y/scale) + font.characters["A"].height

        assets.shd_sdf_font:send("outline", fam.hex"473b78")
		
		for c in text:gmatch(utf8.charpattern) do
			if c == "\n" then
				tx = x / scale
				ty = ty + font.characters["A"].height
			elseif c == "\t" then
				tx = tx + font.characters["A"].width * 4
            elseif c == "*" then
                sw = not sw
                assets.shd_sdf_font:send("thicc", sw and 0.8 or 0.4)
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

ui.text_length = function(font, text, scale)
    local k = font.characters["A"]
    local mtx = 0
    local tx = 0
    local ty = k.height
    
    for c in text:gmatch(utf8.charpattern) do
        if c == "\n" then
            tx = 0
            ty = ty + k.height
        elseif c == "\t" then
            tx = tx + k.width * 4
        elseif c == "*" or c == "~" then
        else
            local t = font.characters[c] or font.characters["?"]
            tx = tx + t.advance
        end

        mtx = math.max(tx, mtx)
    end

    return mtx*scale, (ty+k.height)*scale
end

ui.on_tick = function(self, dt)
    dialog:on_tick(dt)
end

ui.update = function(self, dt)
    dialog:update(dt)
    ui.done = not ui.mode
end

-- TODO: Savefile loading and reading
-- TODO: Settings management

local u_, d_, s_

ui.list = function (items, delta, x, y, w, h, disable)
    items.selected = items.selected or 1
    items.sel_lerp = items.sel_lerp or items.selected

    if not disable then
        if input.holding("up") then
            if not u_ then
                u_ = true
                items.selected = items.selected - 1
                assets.sfx_click:play()
            end
        else
            u_ = false
        end

        if input.holding("down") then
            if not d_ then
                d_ = true
                items.selected = items.selected + 1
                assets.sfx_click:play()
            end
        else
            d_ = false
        end

        if items.selected <= 0 then -- could probs do this with a modulo but im lazy
            items.selected = #items
        elseif items.selected > #items then
            items.selected = 1
        end
    end

    items.sel_lerp = fam.lerp(items.sel_lerp, items.selected, delta * 12)
    
    local th = assets.fnt_atkinson.characters["A"].height / 7
    th = th + 6

    local function draw_options()
        for i, text in ipairs(items) do
            -- fucking EVIL math.
            local y = ((i-1)*th)+(th/4)+1+(th*(#items-items.sel_lerp))
            ui.draw_text(assets.fnt_atkinson, text, 12, y, 1/7)
        end
    end

    lg.push()
        lg.translate(x, y)
        lg.setShader()
            
        lg.setColor(ui.dark)
        lg.rectangle("fill", 0, 0, w, h, 9, 9, 3)

        lg.stencil(function ()
            lg.rectangle("fill", 0, 0, w, h, 9, 9, 3)
        end)
        lg.setStencilTest("greater", 0)

        lg.setShader()

        lg.setColor(ui.clear)
        lg.rectangle("fill", 0, (h/2)-(th/2), w, th)
        draw_options()

        lg.stencil(function ()
            --lg.rectangle("fill", 0, 0, w, h, 9, 9, 3)
            lg.rectangle("fill", 0, (h/2)-(th/2), w, th)
        end)
        lg.setStencilTest("greater", 0)

        lg.setColor(ui.dark)
        lg.push()
            lg.translate(2.5, h/2)
            lg.scale(3)
            lg.polygon("fill", {
                0, -1,
                2, 0,
                0, 1
            })
        lg.pop()
        draw_options()
    lg.pop()

    if input.holding("action") then
        if not s_ then
            s_ = true
            assets.sfx_done:play()
            return true
        end
    else
        s_ = false
    end
end

-- -100 to 100
-- -125 to 125
local function stat_menu(state)
    lg.push("all")

    assets.shd_bwapbwap:send("time", lt.getTime())
    lg.setShader(assets.shd_bwapbwap)
            
    lg.setColor(fam.hex"#18002e")
    lg.rectangle("fill", -40, -90, 80, 20, 9, 9, 3)

    lg.rectangle("fill", -110, -60, 100, 20, 9, 9, 3)

    do -- clock
        local th = math.floor(24 * (state.daytime + 0.25)) % 24
        local h = th % 12
        local p = (th > 12) and "PM" or "AM"
        local m = math.floor(60 * 24 * (state.daytime + 0.25)) % 60
        local hour = ("%02d:%02d %s"):format(h, m, p)

        lg.setColor(1, 1, 1, 1)
        local w, h = ui.text_length(assets.fnt_atkinson, hour, 1/6)
        ui.draw_text(assets.fnt_atkinson, hour, -(w/2), -76.5-(h/2), 1/6)
    end

    lg.pop()
end


ui.draw = function(self, w, h, state)
    assets.shd_bwapbwap:send("time", lt.getTime())

    local t = math.floor(state.daytime * 64)
    --do
    --    local r, g, b = ui.sky_cycle:getPixel(t, 1)
    --    local h, s, l = fam.rgb2hsl(r, g, b)
    --    ui.dark = {fam.hsl(h, 0.3, 0.1)}
    --end

    do
        local r1, g1, b1 = ui.sky_cycle:getPixel(t, 2)
        local r2, g2, b2 = ui.sky_cycle:getPixel(t+0.5, 2)
        local i = t - math.floor(t)
        local h, s, l = fam.rgb2hsl(
            fam.lerp(r1, r2, i),
            fam.lerp(g1, g2, i),
            fam.lerp(b1, b2, i)
        )
        local r, g, b = fam.hsl(math.abs(h), 0.6, 0.9)
        ui.clear = {math.max(r, 0.6), math.max(g, 0.6), math.max(b, 0.6)}
    end

    lg.push("all")
        local s = math.max(1, math.min(w, h)/200)
        lg.scale(s)
        lg.translate(w/s/2, h/s/2)
        --lg.rectangle("fill", 10, 10, 30, 30)

        dialog:draw()
    lg.pop()
end

return ui
