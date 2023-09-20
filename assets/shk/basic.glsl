void pixel() {
    vec4 other = Texel(tex, uv) * color;

    albedo.rgb = other.rgb;
    alpha = other.a;
}