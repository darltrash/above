local vector = require "lib.vec3"

local lk = love.keyboard
local lm = love.mouse
local lg = love.graphics
local lj = love.joystick

local modes = {
    desktop = {
        name = "desktop",
        times = {},
        map = {
            up     = {"w", "up"},
            down   = {"s", "down"},
            left   = {"a", "left"},
            right  = {"d", "right"},
            action = {"return", "z"},

            camera_up    = {"9"},
            camera_down  = {"9"},
            camera_left  = {"q"},
            camera_right = {"e"}
        },

        get_direction = function (self)
            local vector = vector(0, 0)
            local m = self.map

            if lk.isDown(unpack(m.up)) then
                vector.y = -1
            end

            if lk.isDown(unpack(m.left)) then
                vector.x = -1
            end

            if lk.isDown(unpack(m.down)) then
                vector.y = vector.y + 1
            end

            if lk.isDown(unpack(m.right)) then
                vector.x = vector.x + 1
            end

            return vector:normalize()
        end,

        update = function (self)
            local done
            for k, v in pairs(self.map) do
                if lk.isDown(unpack(v)) then
                    self.times[k] = (self.times[k] or 0) +1
                    done = true
                
                else
                    self.times[k] = 0
                    
                end
            end

            return done
        end,

        just_pressed = function (self, what)
            return self.times[what] == 1
        end,

        holding = function (self, what)
            return self.times[what] > 0
        end
    },

    joysticks = {
        name = "joystick",

        map = {
            movement_x = {"axis", 1},
            movement_y = {"axis", 2},
            camera_x = {"axis", 3},
        },

        get_direction = function (self)
            local joysticks = lj.getJoysticks()
            local out = vector(0, 0, 0)

            if #joysticks > 0 then
                out.x = joysticks[1]:getAxis(1)
                out.y = joysticks[1]:getAxis(2)
            end

            return out
        end,

        update = function (self)
            return self:get_direction():magnitude() > 0
        end,

        just_pressed = function ()
            local joysticks = lj.getJoysticks()
        end,

        holding = function ()
            
        end
    }
}
local current = modes.desktop

return {
    update = function ()
        for k, v in pairs(modes) do
            if v:update() then
                current = v
            end
        end
    end,

    get_direction = function ()
        return current:get_direction()
    end,

    just_pressed = function (what)
        return current:just_pressed(what)
    end,

    holding = function (what)
        return current:holding(what)
    end,

    current = function ()
        return current
    end
}
