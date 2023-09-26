#ifdef PIXEL
    float linearstep(float e0, float e1, float x) {
        return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    }

    vec4 blur5(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
		vec4 color = vec4(0.0);
		vec2 off1 = vec2(1.3333333333333333) * direction;
		color += Texel(image, uv) * 0.29411764705882354;
		color += Texel(image, uv + (off1 / resolution)) * 0.35294117647058826;
		color += Texel(image, uv - (off1 / resolution)) * 0.35294117647058826;
		return color;
	}

    uniform float thicc = 1.0;
    uniform vec4 outline = vec4(0.0);

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
        float a = Texel(tex, uv).r;

        vec4 o = vec4(0.0);

        float k = 1.0-mix(0.6, 1.0, thicc);
        float b = linearstep(k, k+0.1, a);
        o += color * b; 

        return o;
    }
#endif
