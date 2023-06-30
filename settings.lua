local mimi = require "lib.mimi"

-- TODO: implement this....

local settings = {
    low_end = false,
    debug = false,
    linear = false,
    no_post = false,
    volume = 1,
    fullscreen = false,
    scale = -1,
}

--[[
        low_end = os.getenv("ABOVE_LOW_END"),
	debug = os.getenv("ABOVE_DEBUG"),
	fps = os.getenv("ABOVE_FPS") or settings.debug,
	linear = os.getenv("ABOVE_LINEAR"),
	no_post = os.getenv("ABOVE_NO_POST") or settings.low_end,
	volume = os.getenv("ABOVE_VOLUME"),
	fullscreen = os.getenv("ABOVE_FULLSCREEN") and true or false,
	scale = os.getenv("ABOVE_SCALE"),
	vsync = tonumber(os.getenv("ABOVE_VSYNC")) or 1,
	level = settings.debug and os.getenv("ABOVE_LEVEL") or nil,
	fps_camera = false
]]