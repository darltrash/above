uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

uniform mat4 inverse_proj;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec3 lc_position;

#define sqr(a) (a * a)

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

        lc_position = vertex_position.xyz;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image back_color;
    uniform Image back_depth;
    uniform Image back_normal;

    uniform vec4 ambient;

    vec3 tonemap_aces(vec3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    // Crazy dither thing
    uniform float dither_table[4*4];

    float dither4x4(vec2 position, float brightness) {
        ivec2 p = ivec2(mod(position, 4.0));
        
        float limit = mix(0.0, dither_table[p.x + p.y * 4], step(float(p.x), 8.0));

        return step(limit, brightness);
    }

    // Ported from Colby's thingy :)
    vec3 calculate_view_position(vec2 uv, float z) {
        // don't allow 0.0/1.0, because the far plane can be infinite
        const float threshold = 0.000001;
        vec4 position_cs = vec4(vec2(uv.x, 1.0 - uv.y) * 2.0 - 1.0, clamp(z, threshold, 1.0-threshold), 1.0);
        vec4 position_vs = inverse_proj * position_cs;
        return position_vs.xyz / position_vs.w;
    }

    void effect() {
        vec3 coords = ((cl_position.xyz / cl_position.w) + 1.0) * 0.5;
        float s_depth = Texel(back_depth, coords.xy).r;

        vec4 o = VaryingColor * ambient;
        if (s_depth != 1.0) {
            vec3 scoords = calculate_view_position(coords.xy, s_depth);
            float dist = clamp(distance(vw_position.xyz, scoords) / 16.0, 0.0, 1.0);
            vec4 c = Texel(back_color, coords.xy);
            o.rgb = mix(c.rgb, o.rgb, 1.0 - ((1.0 - dist) * 0.8));
        }
    
        love_Canvases[0] = o;
        love_Canvases[1] = vec4(vw_normal * 0.5 + 0.5, 1.0);
    }
#endif