local exm = require "lib.iqm"

local ret = {
    shader = lg.newShader("assets/shd_basic.glsl"),
    shader_gradient = lg.newShader("assets/shd_gradient.glsl"),
    shader_water = lg.newShader("assets/shd_water.glsl"),
    shader_copy = lg.newShader("assets/shd_copy.glsl"),
    shader_post = lg.newShader("assets/shd_post.glsl"),
    shader_cubemap = lg.newShader("assets/shd_cubemap.glsl"),

    font = lg.newFont("assets/fnt_monogram.ttf", 16),
    atlas = lg.newImage("assets/atl_main.png"),
    water_mesh = exm.load("assets/mod_water.exm").mesh,
    quad_model = exm.load("assets/mod_quad.exm").mesh,
    step_sound = la.newSource("assets/snd_step.ogg", "static"),
    guarded_place = lg.newImage("assets/atl_guarded_place.png"),
    guarded_music = la.newSource("assets/mus_guarded_place.mp3", "stream"),

    cube = exm.load("assets/mod_cube.exm").mesh,
    aligned_cube = exm.load("assets/mod_aligned_cube.exm").mesh,

    white = lg.newImage("assets/spr_white.png"),

    sky_test = lg.newCubeImage("assets/sky_test.png")
}

ret.quad_model:setTexture(ret.atlas)

local vector = require "lib.vec3"
local noise = love.image.newImageData(256, 256)
noise:mapPixel(function (x, y)
    local n = (vector(
        lm.random(-100, 100)/100,
        lm.random(-100, 100)/100,
        10
    ):normalize() * 1) / 2

    return n.x, n.y, n.z, 1
end)

ret.noise = lg.newImage("assets/spr_noise.png")

return ret