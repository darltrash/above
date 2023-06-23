#pragma language glsl3
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;

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
        vw_normal = cofactor(view * model) * VertexNormal;

        cl_position = projection * vw_position;

        vx_color = VertexColor;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image MainTex;
    uniform Image perlin;

    // Lighting!

    uniform float time;
    uniform vec4 clip;
    uniform float translucent; // useful for displaying flat things

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

    // Actual math
    void effect() {
        // Lighting! (Diffuse)
        vec3 normal = normalize(mix(vw_normal, abs(vw_normal), translucent));
        vec2 uv = VaryingTexCoord.xy * 0.4;
        vec4 o = vec4(0.0);

        if (dither4x4(love_PixelCoord.xy, Texel(perlin, uv + time * 0.01).r) > 0.5)
            o.r = 1.0;

        if (dither4x4(love_PixelCoord.xy, Texel(perlin, uv + time * 0.03).g) > 0.5)
            o.g = 1.0;

        if (dither4x4(love_PixelCoord.xy, Texel(perlin, uv + time * 0.02).b) > 0.5)
            o.b = 1.0;

        if (length(o.rgb) > 0.0)
            o.a = 1.0;

        o *= VaryingColor;

        // If something is very close to the camera, make it transparent!
        o.a *= min(1.0, length(vw_position.xyz) / 2.5);
        
        // Calculate dithering based on transparency, skip dithered pixels!
        if (dither4x4(love_PixelCoord.xy, o.a) < 0.5)
            discard;

        vec3 n = normal * 0.5 + 0.5;

        love_Canvases[0] = vec4(o.rgb*4.0, 1.0);
        love_Canvases[1] = vec4(n, 1.0);
    }
#endif