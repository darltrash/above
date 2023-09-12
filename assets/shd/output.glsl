#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { 
        return vertex; 
    }
#endif

#ifdef PIXEL
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
        vec4 c = Texel(tex, uv);
        return c;
    }
#endif
