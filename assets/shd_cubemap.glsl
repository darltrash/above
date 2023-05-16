uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
varying vec3 uv;

#ifdef VERTEX
	vec4 position(mat4 _, vec4 vertex) { 
        uv = vertex.xyz;
        return projection * view * model * vertex; 
    }
#endif

#ifdef PIXEL
    uniform samplerCube sky_texture;

    vec4 effect(vec4 a, Image b, vec2 c, vec2 screen_coords) {
        return Texel(sky_texture, normalize(uv));
    }
#endif