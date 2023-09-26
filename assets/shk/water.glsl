#define grab

uniform sampler2D back_color;
uniform sampler2D reflection;
uniform sampler2D perlin;
uniform mat4 reflection_matrix;

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

float fres(float ior, float ldh) {
    float f0 = (ior - 1.0) / (ior + 1.0);
    f0 *= f0;
    float x = clamp(1.0 - ldh, 0.0, 1.0);
    float x2 = x * x;
    return (1.0 - f0) * (x2 * x2 * x) + f0;
}

void pixel() {
    vec3 origin = texture(back_color, back_uv).rgb / 120.0;

    float dist = distance(vw_position.xyz, back_position.xyz);
    float t = clamp(dist / 25.0, 0.0, 1.0);
    t *= t;

//    if (t > 1.1) {
//        
//        return;
//    }

    float ior = 1.8 * 100.0 * 0.01;
    float ldh = max(0.25, dot(normal, incoming));
    float fresnel = fres(ior, ldh);

    vec3 k = mix(vec3(0.05, 0.0, 0.2), vec3(0.6, 0.0, 0.7), fresnel);

    albedo.rgb = mix(origin, k, t);

    roughness = 1.0;
    metalness = 0.0;

    vec4 x = projection * reflection_matrix * wl_position;
    vec2 v = (x.xy / x.w) * 0.5 + 0.5;

    albedo.rgb += texture(reflection, v).rgb / 240.0;
}