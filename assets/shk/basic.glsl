uniform sampler2D roughness_map;

void pixel() {
    vec4 other = Texel(tex, uv) * color;

    albedo.rgb = other.rgb;
    alpha = other.a;

    roughness = Texel(roughness_map, uv).r * 0.9;
}
