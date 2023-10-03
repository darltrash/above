#ifdef VERTEX
    uniform float time;

	vec4 position(mat4 mvp, vec4 vertex) { 
        vertex.x += (sin((time * 1.2) + vertex.y)*2.0) * (love_ScreenSize.x / 590.0);
        vertex.y += (sin((time * 1.4) + vertex.x)*2.0) * (love_ScreenSize.y / 590.0);
        return mvp * vertex; 
    }
#endif
