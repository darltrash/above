uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform Image depth_tex;
    uniform Image normal_tex;

    float rand(vec2 co) {
        return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
    }

    vec4 effect(vec4 _a, Image color_tex, vec2 uv, vec2 _b) {
        float depth = Texel(depth_tex, uv).r;
        float ssao = 1.0;

        vec4 color = Texel(color_tex, uv);
        color.rgb *= ssao;

        return color;
    }
#endif