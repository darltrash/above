#pragma language glsl3
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;

varying vec4 wl_position;
varying vec3 wl_normal;

#define sqr(a) (a*a)

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
        vw_position = view * model * vertex_position;
        wl_position = model * vertex_position;

        vw_normal = cofactor(view * model) * VertexNormal;
        wl_normal = cofactor(model) * VertexNormal;

        cl_position = projection * vw_position;

        vx_color = VertexColor;

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

    uniform vec3 harmonics[9];

    uniform float time;
    uniform vec4 clip;
    uniform float translucent; // useful for displaying flat things

    uniform samplerCube cubemap;

    float dither4x4(vec2 position, float brightness) {
        mat4 dither_table = mat4(
            0.0625, 0.5625, 0.1875, 0.6875, 
            0.8125, 0.3125, 0.9375, 0.4375, 
            0.2500, 0.7500, 0.1250, 0.6250, 
            1.0000, 0.5000, 0.8750, 0.3750
        );

        ivec2 p = ivec2(mod(position, 4.0));
        
        float a = step(float(p.x), 3.0);
        float limit = mix(0.0, dither_table[p.y][p.x], a);

        return step(limit, brightness);
    }

    float linearstep(float e0, float e1, float x) {
        return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    }
    
    vec3 sh(vec3 sph[9], vec3 n) {
        vec3 result = sph[0].rgb
            + sph[1].rgb * n.x
            + sph[2].rgb * n.y
            + sph[3].rgb * n.z
            + sph[4].rgb * n.x * n.z
            + sph[5].rgb * n.z * n.y
            + sph[6].rgb * n.y * n.x
            + sph[7].rgb * (3.0 * n.z * n.z - 1.0)
            + sph[8].rgb * n.x * n.x - n.y * n.y
        ;
        return max(result, vec3(0.0));
    }

    #define PI 3.1415926535898

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

    #define saturate(a) (clamp(a, 0.0, 1.0))
    #define fma(a, b, c) ((a) * (b) + (c))
    
    float prefiltered_brdf(float ndv, float roughness) {
        vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
        vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
        vec4 r = roughness * c0 + c1;
        float a004 = min(r.x * r.x, exp2(-9.28 * ndv)) * r.x + r.y;
        vec2 magic = vec2(-1.04, 1.04) * a004 + r.zw;
        return magic.r + magic.g;
    }

    vec3 do_lighting(vec3 albedo, float roughness, float scattering, float metalness, float s_subsurface ){
        vec3 n = normalize(vw_normal);
        vec3 i = normalize(-vw_position.xyz);
        float ndi = max(0.5, dot(n, i));

        roughness = fma(saturate(roughness), 0.98, 0.01);
        float skin = saturate(scattering);
        metalness = saturate(metalness - skin);

        float ior_base = 1.45;
        float ior = fma(metalness, 100.0, ior_base);
        float r2 = roughness * roughness;
        float k = roughness * 0.5;

        vec3 diffuse = vec3(0.0);
        vec3 specular = vec3(0.0);
        vec3 subsurface = vec3(0.0);

        float sun_vis = 1.0; // sample_csm(surface.vs_position);
        float shadow_limit = 0.0;

        for(int i=0; i<light_amount; ++i) { // For each light
            vec3 p = (view * vec4(light_positions[i], 1.0)).xyz;
            vec3 diff = p - vw_position.xyz;

            vec3 l = normalize(diff);
            vec3 c = light_colors[i].rgb * light_colors[i].a;

            float d = max(0.5, length(diff));
            float inv_sqr_law = 1.0 / max(0.1, sqr(d));

            float base_ndl = dot(n, l);
            float ndl = max(0.0, base_ndl);
            float sl = ndl / fma(ndl, (1.0 - k), k);
            float sv = ndi / fma(ndi, (1.0 - k), k);
            float gsf = mix(sl * sv, 1.0, translucent);

            vec3 h = normalize(i + l);
            float ndh = max(0.0, dot(n, h));
            float ldh = max(0.0, dot(l, h));
            float dist = ndh * ndh * (r2 - 1.0);
            float d1 = 1.0 + dist;

            // let ndf = r2 / (pi * d1 * d1) + schlick_ior_fresnel(ior, ldh);
            float ndf = max(r2 / (PI * d1 * d1), schlick_ior_fresnel(ior, ldh)) * gsf;
            vec3 v = c * mix(1.0, sun_vis, float(i == 0));
            diffuse += v * max(shadow_limit, gsf); // limit contrast for now
            subsurface += v * fma(base_ndl * ndi, 0.5, 0.5);
            specular += (v * ndf * smoothstep(0.0, 0.25, ndl)) / max(4.0 * ndl * ndi, 0.001);
        }

        diffuse = mix(diffuse, subsurface * s_subsurface, skin);
        float fresnel = schlick_ior_fresnel(ior, ndi);
        float magic = prefiltered_brdf(ndi, roughness);
        vec3 f0 = mix(vec3(0.04), fma(diffuse, albedo, albedo), fresnel) * magic * 0.01;

        return fma(albedo, diffuse, specular * f0);
    }

    // Actual math
    void effect() {
        // Lighting! (Diffuse)
        vec3 normal = normalize(mix(vw_normal, abs(vw_normal), translucent));
        vec3 sample = textureLod(cubemap, wl_normal, 6.0).rgb;
        float l = length(sample.rgb / 12.0) * 0.1;
        vec3 diffuse = sqrt(sample) * sqr(l); // vec4(sh(harmonics, normal), 1.0)

        float ndi = max(0.5, dot(normal, normalize(-vw_position.xyz)));

        for(int i=0; i<light_amount; ++i) { // For each light
            vec3 position = (view * vec4(light_positions[i], 1.0)).xyz;
            vec3 color = light_colors[i].rgb * light_colors[i].a;

            vec3 diff = position - vw_position.xyz;
            float dist = max(0.0, length(diff));
            float inv_sqr_law = 1.0 / max(0.6, sqr(dist));
            
            vec3 l = normalize(diff);
            float base_ndl = dot(normal, l);

            float roughness = 0.8;

            float k = roughness * 0.5;
            float ndl = max(0.0, base_ndl);
            float sl = ndl / (ndl * (1.0 - k) + k);
            float sv = ndi / (ndi * (1.0 - k) + k);
            float gsf = mix(sl * sv, 1.0, translucent);

            // Now we add our light's color to the light value
            diffuse += color * inv_sqr_law * gsf;
        }

        // This helps us make the models just use a single portion of the 
        // texture, which allows us to make things such as sprites show up :)
        vec2 uv = clip.xy + VaryingTexCoord.xy * clip.zw;

        // Evrathing togetha
        vec4 o = Texel(MainTex, uv) * VaryingColor * vec4(diffuse, 1.0);
        
        // If something is very close to the camera, make it transparent!
        //o.a *= min(1.0, length(vw_position.xyz) / 2.5);
        
        // Calculate dithering based on transparency, skip dithered pixels!
        if (dither4x4(love_PixelCoord.xy, o.a) < 0.5)
            discard;

        vec3 n = normal * 0.5 + 0.5;

        love_Canvases[0] = vec4(o.rgb * (1.0+glow), 1.0);
        love_Canvases[1] = vec4(n, 1.0);
    }
#endif