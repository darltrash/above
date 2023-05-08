#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform vec3 bg_colora;
    uniform vec3 bg_colorb;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        return vec4(gammaCorrectColor(mix(bg_colora, bg_colorb, texture_coords.y)), 1.0);
    }
#endif