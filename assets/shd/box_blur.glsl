#pragma language glsl3

#ifdef PIXEL
	uniform vec2 direction;

	vec4 blur5(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
		vec4 color = vec4(0.0);
		vec2 off1 = vec2(1.3333333333333333) * direction;
		color += Texel(image, uv) * 0.29411764705882354;
		color += Texel(image, uv + (off1 / resolution)) * 0.35294117647058826;
		color += Texel(image, uv - (off1 / resolution)) * 0.35294117647058826;
		return color;
	}

	vec4 blur9(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
		vec4 color = vec4(0.0);
		vec2 off1 = vec2(1.3846153846) * direction;
		vec2 off2 = vec2(3.2307692308) * direction;
		color += Texel(image, uv) * 0.2270270270;
		color += Texel(image, uv + (off1 / resolution)) * 0.3162162162;
		color += Texel(image, uv - (off1 / resolution)) * 0.3162162162;
		color += Texel(image, uv + (off2 / resolution)) * 0.0702702703;
		color += Texel(image, uv - (off2 / resolution)) * 0.0702702703;
		return color;
	}

	vec4 blur13(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
		vec4 color = vec4(0.0);
		vec2 off1 = vec2(1.411764705882353) * direction;
		vec2 off2 = vec2(3.2941176470588234) * direction;
		vec2 off3 = vec2(5.176470588235294) * direction;
		color += Texel(image, uv) * 0.1964825501511404;
		color += Texel(image, uv + (off1 / resolution)) * 0.2969069646728344;
		color += Texel(image, uv - (off1 / resolution)) * 0.2969069646728344;
		color += Texel(image, uv + (off2 / resolution)) * 0.09447039785044732;
		color += Texel(image, uv - (off2 / resolution)) * 0.09447039785044732;
		color += Texel(image, uv + (off3 / resolution)) * 0.010381362401148057;
		color += Texel(image, uv - (off3 / resolution)) * 0.010381362401148057;
		return color;
	}

	vec4 effect(vec4 _, sampler2D tex, vec2 uv, vec2 sc) {
		return blur5(tex, uv, textureSize(tex, 0), direction);
	}
#endif
