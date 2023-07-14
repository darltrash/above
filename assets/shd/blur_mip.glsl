#pragma language glsl3

#ifdef VERTEX
	vec4 position(mat4 _, vec4 vertex) {
		return vec4(sign(vertex.xyz), 1.0);
	}
#endif

#ifdef PIXEL
	uniform vec3 direction_mip;

	vec4 blur5(sampler2D image, vec2 uv, vec2 resolution, vec2 direction, float mip) {
		vec4 color = vec4(0.0);
		vec2 off1 = vec2(1.3333333333333333) * direction;
		color += textureLod(image, uv, mip) * 0.29411764705882354;
		color += textureLod(image, uv + (off1 / resolution), mip) * 0.35294117647058826;
		color += textureLod(image, uv - (off1 / resolution), mip) * 0.35294117647058826;
		return color;
	}

	vec4 blur9(sampler2D image, vec2 uv, vec2 resolution, vec2 direction, float mip) {
		vec4 color = vec4(0.0);
		vec2 off1 = vec2(1.3846153846) * direction;
		vec2 off2 = vec2(3.2307692308) * direction;
		color += textureLod(image, uv, mip) * 0.2270270270;
		color += textureLod(image, uv + (off1 / resolution), mip) * 0.3162162162;
		color += textureLod(image, uv - (off1 / resolution), mip) * 0.3162162162;
		color += textureLod(image, uv + (off2 / resolution), mip) * 0.0702702703;
		color += textureLod(image, uv - (off2 / resolution), mip) * 0.0702702703;
		return color;
	}

	vec4 blur13(sampler2D image, vec2 uv, vec2 resolution, vec2 direction, float mip) {
		vec4 color = vec4(0.0);
		vec2 off1 = vec2(1.411764705882353) * direction;
		vec2 off2 = vec2(3.2941176470588234) * direction;
		vec2 off3 = vec2(5.176470588235294) * direction;
		color += textureLod(image, uv, mip) * 0.1964825501511404;
		color += textureLod(image, uv + (off1 / resolution), mip) * 0.2969069646728344;
		color += textureLod(image, uv - (off1 / resolution), mip) * 0.2969069646728344;
		color += textureLod(image, uv + (off2 / resolution), mip) * 0.09447039785044732;
		color += textureLod(image, uv - (off2 / resolution), mip) * 0.09447039785044732;
		color += textureLod(image, uv + (off3 / resolution), mip) * 0.010381362401148057;
		color += textureLod(image, uv - (off3 / resolution), mip) * 0.010381362401148057;
		return color;
	}

	vec4 effect(vec4 _, sampler2D tex, vec2 uv, vec2 sc) {
		return blur9(tex, uv, textureSize(tex, int(direction_mip.z)), direction_mip.xy, direction_mip.z);
	}
#endif