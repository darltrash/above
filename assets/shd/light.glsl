#pragma language glsl3

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform float threshold = 0.9;
    uniform float exposure;

    float luma(vec3 color) {
        return dot(color, vec3(0.299, 0.587, 0.114));
    }

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
        vec4 o = texture(tex, uv) * color;

        o.rgb *= exp2(exposure);
        
        return normalize(o) * smoothstep(1.0, 2.0, luma(o.rgb)) * 30.0;
    }
#endif
