#define grabby

uniform Image back_color;

void pixel() {
    vec3 wlk_position = wl_position.xyz / wl_position.w;

    float g = 1.0;
    if (mod(wlk_position.x, 2.0) > 1.0)
        g = -g;

    if (mod(wlk_position.z+1.0, 2.0) > 1.0)
        g = -g;

    if (mod(wlk_position.y+1.0, 2.0) > 1.0)
        g = -g;

    albedo.rgb *= 0.5 + max(g * 0.5, 0.0);

    roughness = 0.3 + max(0.0, g) * 0.5;
    metalness = 0.3 + max(0.0, g) * 0.2;
}