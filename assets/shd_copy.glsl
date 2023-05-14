#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform Image MainTex;
    uniform Image color;
    uniform Image normal;

    void effect() {
        gl_FragDepth = Texel(MainTex, VaryingTexCoord.xy).r;
        love_Canvases[0] = Texel(color, VaryingTexCoord.xy);
        love_Canvases[1] = Texel(normal, VaryingTexCoord.xy);
    }
#endif