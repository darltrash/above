#pragma language glsl3

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    // Cool color correction, makes things look cooler.
    vec3 tonemap_aces(vec3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    vec4 effect(vec4 _, Image tex, vec2 uv, vec2 screen_coords) {
        return gammaCorrectColor (
            vec4(tonemap_aces(textureLod(tex, uv, 0.0).rgb * exp2(-0.5)), 1.0)
        );
    }

#endif
