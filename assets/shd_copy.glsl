#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform Image canvas;
	vec4 effect(vec4 color, Image depth_canvas, vec2 uv, vec2 sc) {
		gl_FragDepth = Texel(depth_canvas, uv).r;
		return Texel(canvas, uv);
	}
#endif