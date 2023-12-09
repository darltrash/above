#pragma language glsl3

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

varying vec4 cl_position;

#ifdef VERTEX
    attribute vec3 VertexNormal;

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

    vec4 position( mat4 _, vec4 lc_position ) {

        vec4 v = model * lc_position;
        cl_position = projection * view * v;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image MainTex;

    uniform vec4 clip;

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

    void effect() {
        vec2 uv = clip.xy + VaryingTexCoord.xy * clip.zw;

        // Evrathing togetha
        vec4 o = Texel(MainTex, uv) * VaryingColor;

        if (o.a < 0.5) discard;

        //float depth = (cl_position.z/cl_position.w) * 0.5 + 0.5;
        //love_Canvases[0] = vec4(depth, depth * depth, 0.0, 1.0);
    }
#endif