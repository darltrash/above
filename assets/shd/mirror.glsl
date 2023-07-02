#pragma language glsl3

// vw_*: view space
// cl_*: clip space
// wl_*: world space
// ss_*: shadowmapper clip space

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

uniform mat4 shadow_view;
uniform mat4 shadow_projection;
varying vec4 ss_position;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;
varying vec4 vx_color;

varying vec4 wl_position;
varying vec3 wl_normal;

#define sqr(a) (a*a)

// TODO: Cleanup shader folder (it's filled with garbage that i dont even use)

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
        wl_position = model * vertex_position;
        vw_position = view * model * vertex_position;
        cl_position = projection * view * model * vertex_position;

        vw_normal = cofactor(view * model) * VertexNormal;
        wl_normal = cofactor(model) * VertexNormal;

        vx_color = VertexColor;

        ss_position = shadow_projection * shadow_view * model * vertex_position;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image MainTex;
    uniform vec3 eye;

    uniform samplerCube cubemap;

    // Actual math
    void effect() {
        // Lighting! (Diffuse)
        vec3 normal = normalize(vw_normal);
        
        vec3 i = normalize(wl_position.xyz - eye);

        vec3 point = reflect(i, wl_normal);
        vec4 o = textureLod(cubemap, point, 0.0);

        vec3 n = normal * 0.5 + 0.5;

        love_Canvases[0] = vec4(o.rgb, 1.0);
        love_Canvases[1] = vec4(n, 1.0);
    }
#endif