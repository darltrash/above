#pragma language glsl3

#define sqr(a) ((a) * (a))

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform vec4 color_a;
    uniform vec4 color_b;
    uniform float power;

    uniform sampler2D light;

    uniform float exposure;

    // Cool color correction, makes things look cooler.
    vec3 tonemap_aces(vec3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    float luma(vec3 color) {
        return dot(color, vec3(0.299, 0.587, 0.114));
    }

    vec4 effect(vec4 _, Image tex, vec2 uv, vec2 screen_coords) {
        vec3 c = Texel(tex, uv).rgb;
        float l = luma(c);
        c = mix(c, mix(color_a.rgb, color_b.rgb, l), power);

        c += Texel(light, uv).rgb * 3.0;

        c += length(c) * 0.1;

        return gammaCorrectColor (
            vec4(tonemap_aces(c * exp2(exposure)), 1.0)
        );
    }

#endif
