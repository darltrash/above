#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    vec4 effect(vec4 _c, Image texture, vec2 uv, vec2 _s) {
        gl_FragDepth = Texel(texture, uv).r;
        return vec4(1.0);
    }
#endif