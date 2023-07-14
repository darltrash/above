#pragma language glsl3

#ifdef PIXEL
	uniform float mip_count;

	vec4 effect(vec4 _, sampler2D tex, vec2 uv, vec2 sc) {
		vec4 accum = vec4(0.0);
		for (float i = 0.0; i < mip_count; i += 1.0) {
			accum += textureLod(tex, uv, i) / mip_count;
		} 
		return accum;
	}
#endif