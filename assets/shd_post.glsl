// THIS SHADER TRIES TO IMPLEMENT BOTH BLOOM AND SSAO
// EVEN BETTER IF I CAN GET GTAO TO WORK.

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform Image depth_texture;
    uniform Image normal_texture;
    uniform Image random_texture;
    uniform mat4 inverse_proj;
    uniform mat4 projection;

    uniform int num_samples;
    uniform vec3 samples[64];

    #define PI 3.1415926535898

    //#define PI 3.1415926535897932384626433832795
    #define PI_HALF 1.5707963267948966192313216916398

    #define SSAO_LIMIT 100
    #define SSAO_SAMPLES 4
    #define SSAO_RADIUS 2.5
    #define SSAO_FALLOFF 1.5
    #define SSAO_THICKNESSMIX 0.2
    #define SSAO_MAX_STRIDE 32

    vec3 calculate_view_position(vec2 uv, float z) {
        // don't allow 0.0/1.0, because the far plane can be infinite
        const float threshold = 0.000001;
        vec4 position_cs = vec4(vec2(uv.x, uv.y) * 2.0 - 1.0, clamp(z, threshold, 1.0-threshold), 1.0);
        vec4 position_vs = inverse_proj * position_cs;
        return position_vs.xyz / position_vs.w;
    }

    // Cool color correction, makes things look cooler.
    vec3 tonemap_aces(vec3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    vec3 get_normal(vec2 uv) {
        return normalize(Texel(normal_texture, uv).rgb * 2.0 - 1.0);
    }

    vec3 get_position(vec2 uv) {
        float depth = Texel(depth_texture, uv).r;
        return calculate_view_position(uv, depth);
    }

    vec2 view_to_uv(vec3 view) {
        vec4 o = projection * vec4(view, 1.0);
        return ((o.xy / o.w) + 1.0) / 2.0;
    }

    vec2 get_random(vec2 uv) {
        return normalize(Texel(random_texture, love_ScreenSize.xy * uv / 256.0).xy * 2.0 - 1.0); 
    }

    float ssao_scale = 0.5;
    float ssao_bias = 0.2;
    float ssao_intensity = 1.0;
    float ssao_radius = 0.4;

    // ao :)
    float occlude(vec2 tcoord, vec2 uv, vec3 p, vec3 cnorm) {
        vec3 diff = get_position(tcoord + uv) - p; 
        vec3 v = normalize(diff); 
        float d = length(diff) * ssao_scale; 
        return max(0.0, dot(cnorm, v)-ssao_bias)*(1.0/(1.0+d)) * ssao_intensity;
    }

    vec4 effect(vec4 _, Image texture, vec2 uv, vec2 screen_coords) {
        vec3 view_pos = get_position(uv); 
        vec3 view_norm = get_normal(uv); 

        int iterations = 16; 
        float angle_segment = PI / float(iterations);

        float rad = ssao_radius/view_pos.z; 

        float ao = 0.0; 
        for (int j = 0; j < iterations; j++) {
            float angle = angle_segment * float(j);
            vec2 offset = vec2(sin(angle), cos(angle));
            vec2 coord1 = reflect(offset, get_random(uv))*rad; 
            vec2 coord2 = vec2(
                coord1.x*0.707 - coord1.y*0.707, 
                coord1.x*0.707 + coord1.y*0.707
            ); 
            
            ao += occlude(uv, coord1*0.25, view_pos, view_norm);
            ao += occlude(uv, coord2*0.5,  view_pos, view_norm);
            ao += occlude(uv, coord1*0.75, view_pos, view_norm);
            ao += occlude(uv, coord2,      view_pos, view_norm);
        }
        ao /= float(iterations * 4); 

        // Apply the occlusion to the fragment color
        vec3 color = Texel(texture, uv).rgb * (1.0 - ao);

        return gammaCorrectColor (
            vec4(tonemap_aces(color * exp2(-0.5)), 1.0)
        );
    }

#endif
