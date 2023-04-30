uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform float time;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec2 vw_texcoord;
varying vec3 vw_normal;

const float fog = 0.5;

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

    vec4 position( mat4 _, vec4 vertex_position ) {
        vw_position = view * model * vertex_position;
        vw_normal = cofactor(model) * VertexNormal;
        vw_texcoord = VertexTexCoord.xy;

        cl_position = projection * vw_position;

        return projection * vw_position;
    }
#endif

#ifdef PIXEL
    uniform Image MainTex;

    void effect() {
        love_Canvases[0] = Texel(MainTex, vw_texcoord) * VaryingColor; // color
        //love_Canvases[1] = vec4(normalize(vw_normal), 1.0); // normals
        
        //float dist = distance(vw_position.xyz, vec3(0.0, 0.0, 0.0));
        //o.a *= getFogFactor(dist);
    }
#endif