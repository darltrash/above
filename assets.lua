local exm = require "lib.iqm"

local ret = {
    shader = lg.newShader("assets/shd_basic.glsl"),
    shader_gradient = lg.newShader("assets/shd_gradient.glsl"),

    font = lg.newFont("assets/fnt_monogram.ttf", 16),
    atlas = lg.newImage("assets/atl_main.png"),
    water_mesh = exm.load("assets/mod_water.exm").mesh,
    quad_model = exm.load("assets/mod_quad.exm").mesh,
    step_sound = la.newSource("assets/snd_step.ogg", "static"),
    guarded_place = lg.newImage("assets/atl_guarded_place.png"),
    guarded_music = la.newSource("assets/mus_guarded_place.mp3", "stream"),

    white = lg.newImage("assets/spr_white.png")
}

ret.quad_model:setTexture(ret.atlas)

return ret