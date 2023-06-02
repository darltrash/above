#define sqr(a) (a*a)

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform vec3 bg_colora;
    uniform vec3 bg_colorb;

    void effect() {
        love_Canvases[0] = vec4(mix(bg_colora, bg_colorb, VaryingTexCoord.y), 1.0);
        love_Canvases[1] = vec4(1.0);
    }
#endif