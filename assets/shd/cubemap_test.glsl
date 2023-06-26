#pragma language glsl3
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

varying vec4 lc_position;
varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;

#define sqr(a) (a*a)

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

    // Actual math
    void effect() {
        // Lighting! (Diffuse)
        vec3 normal = normalize(vw_normal);

        vec3 point = reflect(vw_position.xyz, normal);

        vec4 o = textureLod(cubemap, point, 4.0);

        love_Canvases[0] = vec4(o.rgb, 1.0);
        love_Canvases[1] = vec4(normal, 1.0);
    }
#endif