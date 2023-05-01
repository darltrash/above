#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform float time;
    uniform float scale;

    uniform float curvature;
    uniform float barrelDistortion;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec2 uv = (texture_coords.xy / love_ScreenSize.xy) * 2.0 - 1.0;

        // Calculate CRT effect
        float xscale = (1.0 + curvature) * (1.0 - barrelDistortion * uv.y * uv.y);
        float yscale = (1.0 + curvature) * (1.0 - barrelDistortion * uv.x * uv.x);
        uv.x *= xscale;
        uv.y *= yscale;

        // Convert back to [0, 1]
        uv = (uv + 1.0) / 2.0;
        
        return Texel(texture, uv);
    }
#endif