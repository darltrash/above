#pragma language glsl3

#define sqr(a) ((a) * (a))

#pragma language glsl3

#ifdef VERTEX
    out vec4 posPos;

    #define FXAA_SUBPIX_SHIFT (1.0/4.0)
    vec4 position(mat4 mvp, vec4 vertex) {
        vec2 rcpFrame = vec2(1.0/love_ScreenSize.x, 1.0/love_ScreenSize.y);
        posPos.xy = VertexTexCoord.xy;
        posPos.zw = VertexTexCoord.xy - (rcpFrame * (0.5 + FXAA_SUBPIX_SHIFT));

        return mvp * vertex;
    }
#endif

#ifdef PIXEL
    in vec4 posPos;

    uniform int frame_index = 0;
    uniform sampler2D light;
    uniform float exposure;
    bool enable_fxaa = false;

    vec3 FxaaPixelShader(
        vec4 posPos, // Output of FxaaVertexShader interpolated across screen.
        sampler2D tex, // Input texture.
        vec2 rcpFrame // Constant {1.0/frameWidth, 1.0/frameHeight}.
    ) {
        #define FXAA_REDUCE_MIN (1.0/128.0)
        #define FXAA_REDUCE_MUL (1.0/8.0)
        #define FXAA_SPAN_MAX   8.0

        vec3 rgbNW = textureLod(tex, posPos.zw, 0.0).xyz;
        // vec3 rgbNE = textureLod(tex, posPos.zw + rcpFrame.xy * vec2(1.0, 0.0), 0.0).xyz;
        // vec3 rgbSW = textureLod(tex, posPos.zw + rcpFrame.xy * vec2(0.0, 1.0), 0.0).xyz;
        // vec3 rgbSE = textureLod(tex, posPos.zw + rcpFrame.xy * vec2(1.0, 1.0), 0.0).xyz;
        vec3 rgbNE = textureLodOffset(tex, posPos.zw, 0.0, ivec2(1, 0)).xyz;
        vec3 rgbSW = textureLodOffset(tex, posPos.zw, 0.0, ivec2(0, 1)).xyz;
        vec3 rgbSE = textureLodOffset(tex, posPos.zw, 0.0, ivec2(1, 1)).xyz;
        vec3 rgbM  = textureLod(tex, posPos.xy, 0.0).xyz;

        vec3 luma = vec3(0.299, 0.587, 0.114);
        float lumaNW = dot(rgbNW, luma);
        float lumaNE = dot(rgbNE, luma);
        float lumaSW = dot(rgbSW, luma);
        float lumaSE = dot(rgbSE, luma);
        float lumaM  = dot(rgbM,  luma);

        float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
        float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

        vec2 dir;
        dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
        dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

        float dirReduce = max(
            (lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL),
            FXAA_REDUCE_MIN);
        float rcpDirMin = 1.0/(min(abs(dir.x), abs(dir.y)) + dirReduce);
        dir = min(vec2( FXAA_SPAN_MAX,  FXAA_SPAN_MAX),
                max(vec2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX),
                dir * rcpDirMin)) * rcpFrame.xy;

        vec3 rgbA = (1.0/2.0) * (
            textureLod(tex, posPos.xy + dir * (1.0/3.0 - 0.5), 0.0).xyz +
            textureLod(tex, posPos.xy + dir * (2.0/3.0 - 0.5), 0.0).xyz);
        vec3 rgbB = rgbA * (1.0/2.0) + (1.0/4.0) * (
            textureLod(tex, posPos.xy + dir * (0.0/3.0 - 0.5), 0.0).xyz +
            textureLod(tex, posPos.xy + dir * (3.0/3.0 - 0.5), 0.0).xyz);

        float lumaB = dot(rgbB, luma);
        if ((lumaB < lumaMin) || (lumaB > lumaMax))
            return rgbA;

        return rgbB;
    }

    float dither17(vec2 pos, float index_mod_4) {
        return fract(dot(vec3(pos.xy, index_mod_4), vec3(2.0, 7.0, 23.0) / 17.0));
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

    vec4 effect(vec4 _, sampler2D tex, vec2 uv, vec2 coord) {
        vec3 c = vec3(0.0);

        if (enable_fxaa) {
            vec2 rcpFrame = vec2(1.0/love_ScreenSize.x, 1.0/love_ScreenSize.y);
            c = FxaaPixelShader(posPos, tex, rcpFrame);
            vec3 dithered = c * 0.75 + c * dither17(coord, frame_index % 4);
            c = mix(c, dithered, 0.05);
        } else
            c = Texel(tex, uv).rgb;

        c += Texel(light, uv).rgb * 0.0001;

        c += length(c) * 0.1;

        return gammaCorrectColor (
            vec4(tonemap_aces(c * exp2(exposure)), 1.0)
        );
    }

#endif
