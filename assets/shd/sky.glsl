#pragma language glsl3

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;

varying vec4 lc_position;

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
        //vertex_position.z = 1.0;
        
        lc_position = vertex_position;

        vw_position = view * model * vertex_position;
        vw_normal = cofactor(view * model) * VertexNormal;

        cl_position = projection * vw_position;

        vx_color = VertexColor;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image stars;
    uniform Image MainTex;
    uniform float daytime;

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

    float luma(vec3 color) {
        return dot(color, vec3(0.299, 0.587, 0.114));
    }

    // Actual math
    void effect() {
        float t = daytime;
        vec3 a = Texel(MainTex, vec2(t, 0.75)).rgb;
        vec3 b = Texel(MainTex, vec2(t, 0.25)).rgb;

        float m = (lc_position.y + 0.1) * 3.0;
        vec3 o = mix(a, b, clamp(m, 0.0, 1.0));

        if (lc_position.y < 0.0)
            o = b*0.5;

        love_Canvases[0] = vec4(o * 130.0, 1.0);
    }
#endif