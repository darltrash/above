local vector = require "lib.vec3"

local lk = love.keyboard
local lm = love.mouse
local lg = love.graphics
local lj = love.joystick

local timestep = 1/30

local modes = {
    desktop = {
        name = "desktop",
        times = { any = 0 },
        map = {
            up     = {"w", "up"},
            down   = {"s", "down"},
            left   = {"a", "left"},
            right  = {"d", "right"},
            action = {"return", "z"},
            jump   = {"space", "x"}
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

        update = function (self, delta)
            local done
            for name, keys in pairs(self.map) do
                if lk.isDown(unpack(keys)) then
                    self.times[name] = (self.times[name] or 0) + delta
                    done = true
                else
                    self.times[name] = 0
                end
            end
            
            if done then
                self.times.any = self.times.any + delta
            else
                self.times.any = 0
            end

            return done
        end,

        just_pressed = function (self, what)
            local n = self.times[what]
            return n < timestep and n > 0 and n
        end,

        holding = function (self, what)
            local n = self.times[what] or 0
            return n > 0 and n
        end
    },

    joysticks = {
        name = "joystick",
        times = { any = 0 },
        map = {
            action = {1},
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

        update = function (self, delta)
            local joysticks = lj.getJoysticks()

            if #joysticks > 0 then
                for k, v in pairs(self.map) do
                    if joysticks[1]:isDown(unpack(v)) then
                        self.times[k] = (self.times[k] or 0) + delta
                    
                    else
                        self.times[k] = 0
                        
                    end
                end
            end

            return self:get_direction():magnitude() > 0
        end,

        just_pressed = function (self, what)
            local n = self.times[what]
            return n < timestep and n > 0 and n
        end,

        holding = function (self, what)
            local n = self.times[what] or 0
            return n > 0 and n
        end
    }
}
local current = modes.desktop

return {
    update = function (delta)
        for _, mode in pairs(modes) do
            if mode:update(delta) then
                current = mode
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
