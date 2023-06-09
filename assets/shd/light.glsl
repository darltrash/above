#pragma language glsl3

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform float threshold = 0.9;

    float luma(vec3 color) {
        return dot(color, vec3(0.299, 0.587, 0.114));
    }

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
        vec4 o = texture(tex, uv) * color;
        o.rgb *= o.a;
        
        return normalize(o) * smoothstep(0.7, 1.0, luma(o.rgb)) * length(o.rgb*1.1);
    }
#endif
