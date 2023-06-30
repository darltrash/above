#pragma language glsl3

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform sampler2D perlin;
    uniform float time;

    float dither4x4(vec2 position, float brightness) {
        mat4 dither_table = mat4(
            0.0625, 0.5625, 0.1875, 0.6875, 
            0.8125, 0.3125, 0.9375, 0.4375, 
            0.2500, 0.7500, 0.1250, 0.6250, 
            1.0000, 0.5000, 0.8750, 0.3750
        );

        ivec2 p = ivec2(mod(position, 4.0));
        
        float a = step(float(p.x), 3.0);
        float limit = mix(0.0, dither_table[p.y][p.x], a);

        return step(limit, brightness);
    }

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
        vec4 c = Texel(tex, uv) * color;

        // Calculate dithering based on transparency, skip dithered pixels!

        uv = love_PixelCoord.xy / love_ScreenSize.xy;
        c.a *= Texel(perlin, (uv / 3.0)+(time / 10.0)).x;

        if (dither4x4(love_PixelCoord.xy, c.a) < 0.5)
            discard;

        c.a = 1.0;

        return c;
    }

#endif
