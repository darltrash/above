#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return vertex; }
#endif

#ifdef PIXEL
    uniform vec4 ambient;

    vec4 effect(vec4 _, Image tex, vec2 uv, vec2 screen_coords) {
        return vec4(ambient.rgb * ambient.a, 1.0);
    }
#endif