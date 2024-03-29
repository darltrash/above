#pragma language glsl3

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform mat4 inverse_proj;

uniform mat4 shadow_mats[4];
uniform sampler2DShadow shadow_maps[4];

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;
varying vec4 vx_position;

varying vec4 wl_position;
varying vec3 wl_normal;

uniform float time;
uniform bool trim = true;

#define PI 3.1415926535898
#define sqr(a) ((a)*(a))
#define cub(a) ((a)*(a)*(a))
#define saturate(a) (clamp(a, 0.0, 1.0))
#define fma(a, b, c) ((a) * (b) + (c))

// SUPER SPECIAL TEMPLATEY STUFF! 

    uniform Image MainTex;
    uniform Image back_depth;

    float metalness;
    float roughness;
    vec4 color;
    vec3 albedo;
    vec3 normal;
    vec3 incoming;
    vec2 uv;
    float alpha;
    vec3 back_position;
    vec2 back_uv;

#define tex MainTex
#line 1
    <template>
#line 48

// HERE IT ENDS

#ifdef VERTEX
    attribute vec4 VertexWeight;
    attribute vec4 VertexBone;
    attribute vec3 VertexNormal;

    uniform mat4 pose[100];
    uniform bool has_pose = false;

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
        mat4 real_model = model;

        if (has_pose) {
            mat4 skeleton = pose[int(VertexBone.x*255.0)] * VertexWeight.x +
                            pose[int(VertexBone.y*255.0)] * VertexWeight.y +
                            pose[int(VertexBone.z*255.0)] * VertexWeight.z +
                            pose[int(VertexBone.w*255.0)] * VertexWeight.w;
            
            real_model = model * skeleton;
        }

        vw_normal = cofactor(view * real_model) * VertexNormal;
        wl_normal = cofactor(real_model) * VertexNormal;

        vx_position = vertex_position;

#ifdef vertexed
    wl_position = vertex(real_model * vx_position);
#else
    wl_position = real_model * vx_position;
#endif

        vw_position = view * wl_position;
        cl_position = projection * vw_position;

        vx_color = VertexColor;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform float glow;

    // Lighting!
    #define LIGHT_AMOUNT 16
    uniform vec4 ambient;
    uniform vec3 light_positions[LIGHT_AMOUNT];
    uniform vec4 light_colors[LIGHT_AMOUNT];
    uniform int light_amount;

    uniform vec4 clip;
    uniform float translucent = 0.3; // useful for displaying flat things
    uniform float fleshy = 0.5; 

    uniform Image sun_gradient;
    uniform samplerCube cubemap;
    uniform vec3 sun;
    uniform vec3 eye;
    uniform vec3 sun_direction;
    uniform float daytime;

    uniform float grid_mode;

    float dither17(vec2 pos) {
        return fract(dot(pos, vec2(10, 15) / 17.0));
    }

    float dither13(vec2 pos) {
        return fract(dot(pos, vec2(4, 7) / 13.0));
    }

    float linearstep(float e0, float e1, float x) {
        return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    }

    const vec3 luma = vec3(0.299, 0.587, 0.114);

    float gsf(vec3 n, vec3 l, vec3 i) {
        float ndi = max(0.5, dot(n, i));
        float base_ndl = dot(n, l);

        float k = max(0.01, 1.0-roughness) * 0.5;
        float ndl = linearstep(0.0 - fleshy, 1.0, dot(n, l));
        float sl = ndl / (ndl * (1.0 - k) + k);
        float sv = ndi / (ndi * (1.0 - k) + k);

        return mix(sl * sv, 1.0, translucent);
    }

    // visual studio microsoft
    float vsm(sampler2D _sampler, vec4 _shadowCoord, float _bias, float _depthMultiplier, float _minVariance) {
        vec2 texCoord = _shadowCoord.xy/_shadowCoord.w;

        bool outside = any(greaterThan(texCoord, vec2(1.0)))
            || any(lessThan   (texCoord, vec2(0.0)));

        if (outside) {
            return 1.0;
        }

        float receiver = (_shadowCoord.z-_bias)/_shadowCoord.w * _depthMultiplier;
        vec4 rgba = Texel(_sampler, texCoord);
        vec2 occluder = vec2(rgba.x, rgba.x*rgba.x) * _depthMultiplier;

        if (receiver < occluder.x) {
            return 1.0;
        }

        float variance = max(occluder.y - (occluder.x*occluder.x), _minVariance);
        float d = receiver - occluder.x;

        // visibility
        return variance / (variance + d*d);
    }


    float sample_map(int index, vec4 texCoord, float bias) {
        switch (index) {
            case  0: return textureProj(shadow_maps[0], texCoord, bias);
            case  1: return textureProj(shadow_maps[1], texCoord, bias);
            case  2: return textureProj(shadow_maps[2], texCoord, bias);
            default: return textureProj(shadow_maps[3], texCoord, bias);
        }
    }

    float sample_shadow(float bias) {
        for (int i=0; i<2; ++i) {
            vec4 ss_position = shadow_mats[i] * wl_position; 
            ss_position.xyz = ss_position.xyz * 0.5 + 0.5;

            vec2 texCoord = ss_position.xy/ss_position.w;

            bool outside = any(greaterThan(texCoord, vec2(1.0)))
                        || any(lessThan   (texCoord, vec2(0.0)));

            if (outside)
                continue;

            int radius = 1;
            vec2 pixel_size = 1.0 / textureSize(shadow_maps[0], 0);
            float shadow = 0.0;
            ss_position.z -= bias;

            vec4 s = ss_position;

            for (int y=-radius; y<=radius; ++y)
                for (int x=-radius; x<=radius; ++x) {
                    shadow += sample_map(i, vec4(s.xy + vec2(x, y) * pixel_size, s.zw), 0.0);
                }
                
            float a = shadow / pow((radius * 2 + 1), 2);
            
            return a;
        }

        return 1.0;
    }

    vec3 calculate_view_position(vec2 uv, float z) {
        // don't allow 0.0/1.0, because the far plane can be infinite
        const float threshold = 0.000001;
        vec4 position_cs = vec4(vec2(uv.x, 1.0 - uv.y) * 2.0 - 1.0, clamp(z, threshold, 1.0-threshold), 1.0);
        vec4 position_vs = inverse_proj * position_cs;
        return position_vs.xyz / position_vs.w;
    }

    float schlick_ior_fresnel(float ior, float ldh) {
        float f0 = (ior - 1.0) / (ior + 1.0);
        f0 *= f0;
        float x = clamp(1.0 - ldh, 0.0, 1.0);
        float x2 = x * x;
        return (1.0 - f0) * (x2 * x2 * x) + f0;
    }

    float ggx (vec3 N, vec3 V, vec3 L, float ior) {
        float F0 = (ior - 1.0) / (ior + 1.0);
        F0 *= F0;
        float alpha = roughness*roughness;
        vec3 H = normalize(L - V);
        float dotLH = max(0.0, dot(L,H));
        float dotNH = max(0.0, dot(N,H));
        float dotNL = max(0.0, dot(N,L));
        float alphaSqr = alpha * alpha;
        float denom = dotNH * dotNH * (alphaSqr - 1.0) + 1.0;
        float D = alphaSqr / (3.141592653589793 * denom * denom);
        float F = F0 + (1.0 - F0) * pow(1.0 - dotLH, 5.0);
        float k = 0.5 * alpha;
        float k2 = k * k;
        return dotNL * D * F / (dotLH*dotLH*(1.0-k2)+k2);
    }

    float distribution_ggx(vec3 N, vec3 H) {
        float a2     = roughness*roughness;
        float NdotH  = max(dot(N, H), 0.0);
        float NdotH2 = NdotH*NdotH;
        
        float nom    = a2;
        float denom  = (NdotH2 * (a2 - 1.0) + 1.0);
        denom        = PI * denom * denom;
        
        return nom / denom;
    }

    // Actual math
    void effect() {
        if (trim && wl_position.y < 0.001) discard;

        // Lighting! (Diffuse)
        normal = normalize(mix(vw_normal, abs(vw_normal), translucent));
        vec3 s = textureLod(cubemap, normalize(wl_normal), 8).rgb;
        vec3 ambient = s * 1.3; // vec4(sh(harmonics, normal), 1.0)

        vec3 i = normalize(-vw_position.xyz);
        incoming = i;

        // This helps us make the models just use a single portion of the 
        // texture, which allows us to make things such as sprites show up :)
        uv = VaryingTexCoord.xy;
        color = VaryingColor;

        back_uv = love_PixelCoord.xy / love_ScreenSize.xy;

        metalness = 0.0;
        roughness = 1.0;
        albedo = vec3(1.0);
        alpha = 1.0;

        float s_depth = Texel(back_depth, back_uv.xy).r;
        back_position = calculate_view_position(back_uv.xy, s_depth);

        pixel();

        roughness = max(0.08, roughness);

        float ior = metalness * 180.0;
        float ldh = max(0.25, dot(normal, i));
        float fresnel = schlick_ior_fresnel(ior, ldh);
        vec3 kn = normalize(eye-wl_position.xyz);
        vec3 specular = vec3(0.0); //textureLod(cubemap, reflect(kn, wl_normal.xyz), roughness*8.0).rgb * fresnel * 0.05;
        vec3 diffuse = ambient;

        // Rim light at night!
        float rim = gsf(normal, -i, i);
        float nighty = max(0.0, sin((daytime+0.5)*PI*2.0));
        diffuse += rim * 1.3 * s * nighty * roughness;

        for(int k=0; k<light_amount; ++k) { // For each light
            vec3 position = (view * vec4(light_positions[k], 1.0)).xyz;
            vec3 light_color = light_colors[k].rgb * light_colors[k].a;

            // Calculate the inverse square law thing
            vec3 diff = position - vw_position.xyz;
            float dist = max(0.0, length(diff));
            float inv_sqr_law = 1.0 / max(0.9, sqr(dist));
            
            vec3 l = normalize(diff);
            float d = gsf(normal, l, i);
            float s = distribution_ggx(normal, normalize(i + diff));

            // Now we add our light's color to the light value
            diffuse  += light_color * inv_sqr_law * d;
            specular += light_color * inv_sqr_law * s * 0.2;
        }
   
        {
            float daily = max(pow(sin(daytime*2*PI), 0.2), 0);
            //vec3 sun_color = textureLod(cubemap, sun_direction, 10).rgb * 0.02 * daily;

            vec3 sun_color = texture(sun_gradient, vec2(daytime, 1.0)).rgb;

            vec3 vs = (view * vec4(sun_direction, 0.0)).xyz;

            float bias = max(0.002 * (1.0 - dot(normal, vs)), 0.0005);
            float shadow = sample_shadow(bias);
            float d = gsf(normal, vs, i);
            float s = ggx(normal, i, normalize(vs - vw_position.xyz), ior);

            diffuse  += shadow * sun_color * d * 50.0;
            specular += shadow * sun_color * s * 0.2 * daily;

            vec3 vsk = (view * vec4(sun_direction * vec3(-1.0, -1.0, 1.0), 0.0)).xyz;
            float dk = gsf(normal, vsk, i);
            float sk = ggx(normal, i, normalize(vsk - vw_position.xyz), ior);

            diffuse += nighty * dk * 40.0 * vec3(0.1, 0.2, 1.0);
            specular += nighty * sk * 0.2 * daily;
        }

        vec4 o = vec4((albedo * diffuse) + specular, alpha);

        //o.a *= min(1.0, length(vw_position)/2.0);

        // Calculate dithering based on transparency, skip dithered pixels!
        float di = o.a + dither13(love_PixelCoord.xy);
        if (di < 1.0)
            discard;

        vec3 n = normal * 0.5 + 0.5;

        love_Canvases[0] = vec4(o.rgb * (1.0+glow), 1.0);
        love_Canvases[1] = vec4(n, 1.0);
    }
#endif