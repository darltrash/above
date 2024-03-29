local vector = require "lib.vec3"

local lk = love.keyboard
local lm = love.mouse
local lg = love.graphics
local lj = love.joystick

-- TODO: Add proper joystick button input support
-- TODO: Add mobile controls? not entirely sure

local modes = {
    desktop = {
        name = "desktop",
        times = {},
        map = {
            up     = { "w", "up" },
            down   = { "s", "down" },
            left   = { "a", "left" },
            right  = { "d", "right" },
            action = { "return", "z" },
            jump   = { "space", "x" },
            menu   = { "escape" },
            items  = { "c", "rshift" }
        },

        get_direction = function(self)
            local vector = vector(0, 0, 0)
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

        get_camera_movement = function (self)
            local o = vector(0, 0)
            if self.mouse_grabbed then
                o = vector(love.mouse.getPosition()) - 300
                love.mouse.setPosition(300, 300)
            end

            return o
        end,

        update = function(self)
            self.mouse_grabbed = love.mouse.isDown(1)
            love.mouse.setRelativeMode(self.mouse_grabbed)
            love.mouse.setGrabbed(self.mouse_grabbed)

            local done
            for k, v in pairs(self.map) do
                if lk.isDown(unpack(v)) then
                    self.times[k] = (self.times[k] or 0) + 1
                    done = true
                else
                    self.times[k] = 0
                end
            end

            if done then
                self.times.any = (self.times.any or 0) + 1
            else
                self.times.any = 0
            end

            return done
        end,

        just_pressed = function(self, what)
            return self.times[what] == 1
        end,

        holding = function(self, what)
            return self.times[what] > 0
        end
    },

    joysticks = {
        name = "joystick",
        times = {},
        map = {
            action = { 1 },
        },

        get_direction = function(self)
            local joysticks = lj.getJoysticks()
            local out = vector(0, 0, 0)

            if #joysticks > 0 then
                out.x = joysticks[1]:getAxis(1)
                out.y = joysticks[1]:getAxis(2)
            end

            return out
        end,

        update = function(self)
            local joysticks = lj.getJoysticks()

            if #joysticks > 0 then
                for k, v in pairs(self.map) do
                    if joysticks[1]:isDown(unpack(v)) then
                        self.times[k] = (self.times[k] or 0) + 1
                    else
                        self.times[k] = 0
                    end
                end
            end

            return self:get_direction():magnitude() > 0
        end,

        just_pressed = function(self, what)
            return (self.times[what] or 0) == 1
        end,

        holding = function(self, what)
            return (self.times[what] or 0) > 0
        end
    }
}
local current = modes.desktop

return {
    update = function()
        for _, mode in pairs(modes) do
            if mode:update() then
                current = mode
            end
        end
    end,

    get_direction = function()
        return current:get_direction()
    end,

    get_camera_movement = function ()
        return current:get_camera_movement()
    end,

    just_pressed = function(what)
        return current:just_pressed(what)
    end,

    holding = function(what)
        return current:holding(what)
    end,

    current = function()
        return current
    end
}
