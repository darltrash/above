#pragma language glsl3

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

uniform mat4 inverse_proj;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec3 lc_position;

#define sqr(a) ((a) * (a))

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
    uniform vec2 resolution;
    uniform float time;

    vec3 tonemap_aces(vec3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    float dither4x4(vec2 position, float brightness) {
        mat4 dither_table = mat4(
            0.0625, 0.5625, 0.1875, 0.6875, 
            0.8125, 0.3125, 0.9375, 0.4375, 
            0.2500, 0.7500, 0.1250, 0.6250, 
            1.0000, 0.5000, 0.8750, 0.3750
        );

        ivec2 p = ivec2(mod(position, 4.0));
        
        float a = step(p.x, 3);
        float limit = mix(0.0, dither_table[p.y][p.x], a);

        return step(limit, brightness);
    }
    
    // Ported from Excessive's thingy :)
    vec3 calculate_view_position(vec2 uv, float z) {
        // don't allow 0.0/1.0, because the far plane can be infinite
        const float threshold = 0.000001;
        vec4 position_cs = vec4(vec2(uv.x, 1.0 - uv.y) * 2.0 - 1.0, clamp(z, threshold, 1.0-threshold), 1.0);
        vec4 position_vs = inverse_proj * position_cs;
        return position_vs.xyz / position_vs.w;
    }

    float luma(vec3 color) {
        return dot(color, vec3(0.299, 0.587, 0.114));
    }

    void effect() {
        vec3 coords = ((cl_position.xyz / cl_position.w) + 1.0) * 0.5;

        float s_depth = Texel(back_depth, coords.xy).r;
        vec3 position = calculate_view_position(coords.xy, s_depth);
        
        float pi  = 3.1415926535898;
        float pi2 = 6.2831853071796;
    
        float directions = 16.0; // BLUR DIRECTIONS (Default 16.0 - More is better but slower)
        float quality = 3.0; // BLUR QUALITY (Default 4.0 - More is better but slower)
        float size = 8.0; 
    
        vec2 radius = size/resolution;
        vec4 color = texture(back_color, coords.xy);
        
        for( float d=0.0; d<pi2; d+=pi2/directions) {
            for(float i=1.0/quality; i<=1.0; i+=1.0/quality) {
                color += texture(back_color, coords.xy+vec2(cos(d),sin(d))*radius*i);		
            }
        }
        
        color /= (quality + 1.0) * directions - 15.0;

        love_Canvases[0] = color*0.8;
        love_Canvases[1] = vec4(vw_normal * 0.5 + 0.5, 1.0);
    }
#endif