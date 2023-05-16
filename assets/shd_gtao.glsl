#pragma language glsl3
// THIS SHADER TRIES TO IMPLEMENT BOTH BLOOM AND SSAO
// EVEN BETTER IF I CAN GET GTAO TO WORK.

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform Image depth_texture;
    uniform Image normal_texture;
    uniform mat4 inverse_proj;
    uniform mat4 projection;

    uniform int frame;

    #define PI      3.1415926535897932384626433832795
    #define PI_HALF 1.5707963267948966192313216916398

    #define SSAO_LIMIT 40
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
    
    float IntegrateArc(float h1, float h2, float n) {
        float cosN = cos(n);
        float sinN = sin(n);
        return 0.25 * (-cos(2.0 * h1 - n) + cosN + 2.0 * h1 * sinN - cos(2.0 * h2 - n) + cosN + 2.0 * h2 * sinN);
    }

    // Used to get vector from camera to pixel
    // These are offsets that change every frame, results are accumulated using temporal filtering in a separate shader
    // uniform float angleOffset = 0.0;
    // uniform float spatialOffset = 0.0;

    void SliceSample(sampler2D s_depth, float aspect, vec2 tc_base, vec2 aoDir, int i, float targetMip, vec3 ray, vec3 v, inout float closest) {
        vec2 uv = tc_base + aoDir * i;
        float depth = textureLod(s_depth, uv, targetMip).x;
        vec3 p = calculate_view_position(uv, depth) - ray;
        float current = dot(v, normalize(p));
        float falloff = clamp((SSAO_RADIUS - length(p)) / SSAO_FALLOFF, 0.0, 1.0);
        if (current > closest) {
            closest = mix(closest, current, falloff);
        }
        closest = mix(closest, current, SSAO_THICKNESSMIX * falloff);
    }

    float gtao(sampler2D s_depth, float dhere, vec3 normal, vec2 tc_original, vec2 viewsizediv, float angleOffset, float spatialOffset) {	
        if (dhere == 1.0 || dhere == 0.0) {
            return 1.0;
        }

        float aspect = love_ScreenSize.x / love_ScreenSize.y;

        // Vector from camera to the current pixel's position
        vec3 ray = calculate_view_position(tc_original, dhere);
        
        // Calculate the distance between samples (direction vector scale) so that the world space AO radius remains constant but also clamp to avoid cache thrashing
        float stride = min((1.0 / length(ray)) * SSAO_LIMIT, SSAO_MAX_STRIDE);
        vec2 dirMult = viewsizediv.xy * stride;
        // Get the view vector (normalized vector from pixel to camera)
        vec3 v = normalize(-ray);

        // Calculate slice direction from pixel's position
        float dirAngle = (PI / 16.0) * (((int(gl_FragCoord.x) + int(gl_FragCoord.y) & 3) << 2) + (int(gl_FragCoord.x) & 3)) + angleOffset;
        vec2 aoDir = dirMult * vec2(sin(dirAngle), cos(dirAngle));
        
        // Project world space normal to the slice plane
        vec3 toDir = calculate_view_position(tc_original + aoDir, dhere);
        vec3 planeNormal = normalize(cross(v, -toDir));
        vec3 projectedNormal = normal - planeNormal * dot(normal, planeNormal);
        
        // Calculate angle n between view vector and projected normal vector
        vec3 projectedDir = normalize(normalize(toDir) + v);
        float n = acos(dot(-projectedDir, normalize(projectedNormal))) - PI_HALF;
        
        // Init variables
        float c1 = -1.0;
        float c2 = -1.0;
        
        vec2 tc_base = tc_original + aoDir * (0.25 * ((int(gl_FragCoord.y) - int(gl_FragCoord.x)) & 3) - 0.375 + spatialOffset);
        
        const float minMip = 0.0;
        const float maxMip = 3.0;
        const float mipScale = 1.0 / 12.0;
        
        float targetMip = floor(clamp(pow(stride, 1.3) * mipScale, minMip, maxMip));
        
        // Find horizons of the slice
        for (int i = -1; i >= -SSAO_SAMPLES; i--) {
            SliceSample(s_depth, aspect, tc_base, aoDir, i, targetMip, ray, v, c1);
        }

        for (int i = 1; i <= SSAO_SAMPLES; i++) {
            SliceSample(s_depth, aspect, tc_base, aoDir, i, targetMip, ray, v, c2);
        }
        
        // Finalize
        float h1a = -acos(c1);
        float h2a = acos(c2);
        
        // Clamp horizons to the normal hemisphere
        float h1 = n + max(h1a - n, -PI_HALF);
        float h2 = n + min(h2a - n, PI_HALF);
        
        return mix(1.0, IntegrateArc(h1, h2, n), length(projectedNormal));
    }

    // http://aras-p.info/texts/CompactNormalStorage.html
    //vec3 normal_decode(vec4 enc) {
    //    vec2 fenc = enc.xy * 4.0 - 2.0;
    //    float f = dot(fenc, fenc);
    //    float g = sqrt(1.0 - f / 4.0);
    //    return vec3(
    //        fenc * g,
    //        1.0 - f / 2.0
    //    );
    //}

    // halton low discrepancy sequence, from https://www.shadertoy.com/view/wdXSW8
    vec2 halton(int index) {
        const vec2 coprimes = vec2(2.0, 3.0);
        vec2 s = vec2(index, index);
        vec4 a = vec4(1.0, 1.0, 0.0, 0.0);
        while (s.x > 0. && s.y > 0.) {
            a.xy = a.xy/coprimes;
            a.zw += a.xy*mod(s, coprimes);
            s = floor(s/coprimes);
        }
        return a.zw;
    }

    vec4 effect(vec4 _, Image tex, vec2 uv, vec2 screen_coords) {
        vec3 normal = get_normal(uv);
        float z = textureLod(depth_texture, uv, 0.0).r;

        vec2 offset = halton(frame % 4 + 1) - 0.5;
        float a = offset.x;
        float b = offset.y * SSAO_RADIUS;

        vec2 inv_viewport = 1.0 / love_PixelCoord.xy;

        float ao = 0.0;
        ao += gtao(depth_texture, z, normal, uv, inv_viewport, a*1.0, b*1.0);
        ao += gtao(depth_texture, z, normal, uv, inv_viewport, a*1.5, b*1.5);
        ao += gtao(depth_texture, z, normal, uv, inv_viewport, a*3.0, b*3.0);
        ao += gtao(depth_texture, z, normal, uv, inv_viewport, a*4.5, b*4.5);
        ao *= 1.0 / 4.0;

        return vec4(ao, ao, ao, 1.0);
    }

#endif
