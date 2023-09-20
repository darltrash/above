#define grab

uniform sampler2D back_color;

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

void pixel() {
    vec3 origin = texture(back_color, back_uv).rgb / 120.0;

    float dist = distance(vw_position.xyz, back_position.xyz);
    float t = clamp(0.0, 1.0, dist / 25.0);
    t *= t;

    albedo.rgb = mix(origin, vec3(0.05, 0.0, 0.2), t);

    roughness = 0.0;
    metalness = 0.5;

    //if (length(vw_position.xyz) > 60.0) roughness = 1.0;
}