#pragma language glsl3

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;
varying vec3 wl_normal;

varying vec4 lc_position;

#define PI 3.1415926535898

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
        
        wl_normal = (model * vertex_position).xyz;
    
        lc_position = vertex_position;

        vw_position = view * model * vertex_position;
        vw_normal = cofactor(view * model) * VertexNormal;

        cl_position = projection * vw_position;

        vx_color = VertexColor;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image MainTex;
    uniform samplerCube cubemap;
    uniform float daytime;

    float dither13(vec2 pos) {
        return fract(dot(pos, vec2(4, 7) / 13.0));
    }

    // Actual math
    void effect() {
        vec3 s = textureLod(cubemap, normalize(abs(wl_normal)), 8).rgb;

        float a = Texel(MainTex, VaryingTexCoord.xy).a;

        float di = a + dither13(love_PixelCoord.xy);
        if (di < 1.0)
            discard;

        float nighty = max(0.0, sin((daytime+0.5)*PI*2.0));

        love_Canvases[0] = vec4(s * 1.3 * (1.0-(nighty*0.4)), 1.0);
    }
#endif