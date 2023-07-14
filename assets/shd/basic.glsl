#pragma language glsl3

// vw_*: view space
// cl_*: clip space
// wl_*: world space
// ss_*: shadowmapper clip space

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

uniform mat4 shadow_view;
uniform mat4 shadow_projection;
varying vec4 ss_position;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;

varying vec4 wl_position;
varying vec3 wl_normal;

#define PI 3.1415926535898
#define sqr(a) ((a)*(a))
#define cub(a) ((a)*(a)*(a))
#define saturate(a) (clamp(a, 0.0, 1.0))
#define fma(a, b, c) ((a) * (b) + (c))

// TODO: Cleanup shader folder (it's filled with garbage that i dont even use)

// Spherical harmonics, cofactor and improved diffuse
// by the people at excessive ❤ moé 

#ifdef VERTEX
    attribute vec3 VertexNormal;

    // the thang that broke a month ago and i didnt even know about it
    mat3 cofactor(mat4 _m) {
        return mat3(
            _m[1][1]*_m[2][2]-_m[1][2]*_m[2][1],
            _m[1][2]*_m[2][0]-_m[1][0]*_m[2][2],
            _m[1][0]*_m[2][1]-_m[1][1]*_m[2][0],
            _m[0][2]*_m[2][1]-_m[0][1]*_m[2][2],
            _m[0][0]*_m[2][2]-_m[0][2]*_m[2][0],
            _m[0][1]*_m[2][0]-_m[0][0]*_m[2][1],
            _m[0][1]*_m[1][2]-_m[0][2]*_m[1][1],
            _m[0][2]*_m[1][0]-_m[0][0]*_m[1][2],
            _m[0][0]*_m[1][1]-_m[0][1]*_m[1][0]
        );
    }

    vec4 position( mat4 _, vec4 vertex_position ) {
        wl_position = model * vertex_position;
        vw_position = view * model * vertex_position;
        cl_position = projection * view * model * vertex_position;

        vw_normal = cofactor(view * model) * VertexNormal;
        wl_normal = cofactor(model) * VertexNormal;

        vx_color = VertexColor;

        ss_position = shadow_projection * shadow_view * model * vertex_position;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image MainTex;

    uniform float glow;

    // Lighting!
    #define LIGHT_AMOUNT 16
    uniform vec4 ambient;
    uniform vec3 light_positions[LIGHT_AMOUNT];
    uniform vec4 light_colors[LIGHT_AMOUNT];
    uniform int light_amount;

    uniform float time;
    uniform vec4 clip;
    uniform float translucent; // useful for displaying flat things

    uniform sampler2DShadow shadow_map;

    uniform samplerCube cubemap;
    uniform vec3 sun;
    float daytime;
    uniform sampler2D sun_gradient;

    float dither4x4(vec2 position, float brightness) {
        float dither_table[16] = float[16](
            0.0625, 0.5625, 0.1875, 0.6875, 
            0.8125, 0.3125, 0.9375, 0.4375, 
            0.2500, 0.7500, 0.1250, 0.6250, 
            1.0000, 0.5000, 0.8750, 0.3750
        );

        ivec2 p = ivec2(mod(position, 4.0));
        
        float a = step(float(p.x), 3.0);
        float limit = mix(0.0, dither_table[p.y + p.x * 4], a);

        return step(limit, brightness);
    }

    float linearstep(float e0, float e1, float x) {
        return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    }

    float DistributionGGX(vec3 N, vec3 H, float a) {
        float a2     = a*a;
        float NdotH  = max(dot(N, H), 0.0);
        float NdotH2 = NdotH*NdotH;
        
        float nom    = a2;
        float denom  = (NdotH2 * (a2 - 1.0) + 1.0);
        denom        = PI * denom * denom;
        
        return nom / denom;
    }

    vec3 fresnel_schlick(float t, vec3 F0) {
        return F0 + (1.0 - F0) * pow(1.0 - t, 5.0);
    }

    float schlick_ior_fresnel(float ior, float ldh) {
        float f0 = (ior - 1.0) / (ior + 1.0);
        f0 *= f0;
        float x = clamp(1.0 - ldh, 0.0, 1.0);
        float x2 = x * x;
        return (1.0 - f0) * (x2 * x2 * x) + f0;
    }

    const vec3 luma = vec3(0.299, 0.587, 0.114);

    // TODO: Implement Manta's batshit insane shading model? 
/*
    float sample_depth_index(int i, vec4 uv) {
        switch (i) {
            case 0: return textureProj(shadow_maps[0], uv); break;
            case 1: return textureProj(shadow_maps[1], uv); break;
            case 2: return textureProj(shadow_maps[2], uv); break;
            case 3: return textureProj(shadow_maps[3], uv); break;
            default: break;
        }
        return 1.0;
    }

    float sample_pcf(int i, vec4 uv, float _bias, float blur) {
        float bias = (pow(float(i), 1.5)+1.0)*_bias;
        float result = sample_depth_index(i, uv - vec4(0.0, 0.0, bias, 0.0));

        // faster
        return clamp(1.0 - result, 0.0, 1.0);

        result += sample_depth_index(i, vec4(uv.xy + vec2(-0.326212,-0.405805) * blur, uv.z - bias, uv.w));
        result += sample_depth_index(i, vec4(uv.xy + vec2(-0.840144,-0.073580) * blur, uv.z - bias, uv.w));
        result += sample_depth_index(i, vec4(uv.xy + vec2(-0.695914, 0.457137) * blur, uv.z - bias, uv.w));
        result += sample_depth_index(i, vec4(uv.xy + vec2(-0.203345, 0.620716) * blur, uv.z - bias, uv.w));
        result += sample_depth_index(i, vec4(uv.xy + vec2( 0.962340,-0.194983) * blur, uv.z - bias, uv.w));
        result += sample_depth_index(i, vec4(uv.xy + vec2( 0.473434,-0.480026) * blur, uv.z - bias, uv.w));
        result += sample_depth_index(i, vec4(uv.xy + vec2( 0.519456, 0.767022) * blur, uv.z - bias, uv.w));
        return clamp(1.0 - result/8.0, 0.0, 1.0);
    }

    float sample_csm(vec3 pos_vs, float bias) {
        vec2 res = vec2(textureSize(shadow_maps[0], 0));
        float visibility = 1.0;
        for (int i = 0; i < 4; i++) {
            const vec2 sbias = vec2(0.5, 1.0);
            vec4 coord = shadow_matrix[i] * vec4(pos_vs, 1.0);
            coord.xyz *= sbias.xxx;
            coord.xyz += sbias.xxx;
            coord.z *= sbias.y;

            vec3 shadow_coord = coord.xyz / coord.w;
            vec2 minmax = vec2(0.0, 1.0);
            bool inside = all(greaterThan(shadow_coord.xy, minmax.xx)) && all(lessThan(shadow_coord.xy, minmax.yy));
            
            if (inside)
                return sample_pcf(i, coord, bias, 1.0 / res.x);
        }
        return visibility;
    }

    float sample_csm_blended(vec3 pos_vs, float blend_factor, float texel_padding, float bias) {
        return sample_csm(pos_vs, bias);

        vec2 size = textureSize(shadow_maps[0], 0);
        vec2 sel_min = vec2(1.0) / size * texel_padding;
        vec2 sel_max = vec2(1.0) - sel_min;
        vec4 max_dist = vec4(0.0);
        int count = 0;

        mat4 shadow_pos = mat4(0.0);
        ivec2 pair = ivec2(0);
        for (int i = 0; i < 4; i++) {
            const vec2 sbias = vec2(0.5, 1.0);
            vec4 coord = shadow_matrix[i] * vec4(pos_vs, 1.0);
            coord.xyz *= sbias.xxx;
            coord.xyz += sbias.xxx;
            coord.z *= sbias.y;
            shadow_pos[i] = coord;

            vec3 tcs = shadow_pos[i].xyz / shadow_pos[i].w;
            bool selection = all(greaterThan(tcs.xy, sel_min)) && all(lessThan(tcs.xy, sel_max));
            max_dist[i] = max(distance(tcs.x, 0.5), distance(tcs.y, 0.5));
            if (selection && count < 2) {
                pair[count] = i;
                count++;
            }
        }

        float visibility = 1.0;
        if (count > 0) {
            int i0 = pair[0];
            float res_blur = 1.0/size.x;
            const float blur_mix = 0.25;
            float blur0 = mix(res_blur, (5.0-float(i0))/size.x, blur_mix);
            float a = sample_pcf(i0, shadow_pos[i0], bias, blur0);
            float dist = max_dist[i0];
            float factor = smoothstep(0.5 - blend_factor, 0.5, dist);
            float b = 1.0;
            if (count > 1) {
                int i1 = pair[1];
                float blur1 = mix(res_blur, (5.0-float(i1))/size.x, blur_mix);
                b = sample_pcf(i1, shadow_pos[i1], bias, blur1);
            }
            visibility = mix(a, b, factor);
        }
        
        return visibility;
    }
*/
    float slope_scaled_bias(float ndl, float factor) {
        float cosAlpha = ndl;
        float sinAlpha = sqrt(1.0 - cosAlpha * cosAlpha); // sin(acos(L*N))
        float tanAlpha = sinAlpha / cosAlpha;             // tan(acos(L*N))
        return tanAlpha * factor;
    }

    float prefiltered_brdf(float ndv, float roughness) {
        vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
        vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
        vec4 r = roughness * c0 + c1;
        float a004 = min(r.x * r.x, exp2(-9.28 * ndv)) * r.x + r.y;
        vec2 magic = vec2(-1.04, 1.04) * a004 + r.zw;
        return magic.r + magic.g;
    }

    // Actual math
    void effect() {
        // Lighting! (Diffuse)
        vec3 normal = normalize(mix(vw_normal, abs(vw_normal), translucent));
        vec3 sample = textureLod(cubemap, normalize(wl_normal), 7).rgb;
        vec3 ambient = sample * sample * 0.005; // vec4(sh(harmonics, normal), 1.0)

        vec3 diffuse = vec3(0.0, 0.0, 0.0);

        float ndi = max(0.5, dot(normal, normalize(-vw_position.xyz)));

        for(int i=0; i<light_amount; ++i) { // For each light
            vec3 position = (view * vec4(light_positions[i], 1.0)).xyz;
            vec3 color = light_colors[i].rgb * light_colors[i].a;

            vec3 diff = position - vw_position.xyz;
            float dist = max(0.0, length(diff));
            float inv_sqr_law = 1.0 / max(0.9, sqr(dist));
            
            vec3 l = normalize(diff);
            float base_ndl = dot(normal, l);

            float roughness = 0.8;

            float k = roughness * 0.5;
            float ndl = max(0.0, base_ndl);
            float sl = ndl / (ndl * (1.0 - k) + k);
            float sv = ndi / (ndi * (1.0 - k) + k);
            float gsf = mix(sl * sv, 1.0, translucent);

            // Now we add our light's color to the light value
            float brdf = prefiltered_brdf(ndi, roughness);
            diffuse += color * inv_sqr_law * gsf * brdf;
        }
        
        vec3 l_coords = ss_position.xyz / ss_position.w;
        if (l_coords.z <= 1.0f) {
            float shadow = 0.0;

            vec3 l = normalize(sun - wl_position.xyz);
            float base_ndl = abs(dot(wl_normal, l));
            float ndl = max(0.0, base_ndl);

            // FIXME: this code is shite, fix the appimage bugging out horribly
            // TODO: Implement proper biasing, because this one sucks
            // TODO: Implement proper CSM, because uhh, yeah
            // TODO: Implement proper filtering, probably through poisson disks things
            // TODO: do all of the things above

            // suicide doesnt seem like a bad option anymore

            float bias = slope_scaled_bias(ndl, 0.001) * 0.08;
            bias = 0.00005;

            vec4 s = ss_position;
            s.xyz = s.xyz * 0.5 + 0.5;
            s.z -= bias;

            shadow = textureProj(shadow_map, s);

            // float base_ndl = dot(normal, sun);
            // float ndl = max(0.0, base_ndl);
            // float slope_bias = slope_scaled_bias(ndl, 0.001) * 0.05;
            // float shadow = sample_csm_blended(vw_position.xyz, 0.05, 0.0, slope_bias);
            // 

            // FIXME: Sun gradient fricking things up
            diffuse += shadow * 60.0;// * Texel(sun_gradient, vec2(daytime, 0.5)).rgb;
        }

        // This helps us make the models just use a single portion of the 
        // texture, which allows us to make things such as sprites show up :)
        vec2 uv = clip.xy + VaryingTexCoord.xy * clip.zw;

        // TODO: Add 
        // Evrathing togetha
        vec4 o = Texel(MainTex, uv) * VaryingColor * vec4(diffuse + ambient, 1.0);
        
        // FIXME: Bizarre NVIDIA bug around this part
        // If something is very close to the camera, make it transparent!
        o.a *= min(1.0, length(vw_position.xyz) / 2.5);
        
        // Calculate dithering based on transparency, skip dithered pixels!
        if (dither4x4(love_PixelCoord.xy, o.a) < 0.5)
            discard;

        vec3 n = normal * 0.5 + 0.5;

        love_Canvases[0] = vec4(o.rgb * (1.0+glow), 1.0);
        love_Canvases[1] = vec4(n, 1.0);
    }
#endif