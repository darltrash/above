uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
varying vec3 uv;

uniform sampler2D perlin;
uniform sampler2D stars;
uniform float daytime;

#ifdef VERTEX
	vec4 position(mat4 _, vec4 vertex) { 
        uv = vertex.xyz;
        return projection * view * model * vertex; 
    }
#endif

#ifdef PIXEL
    uniform samplerCube cubemap;

    vec4 effect(vec4 a, Image b, vec2 c, vec2 screen_coords) {
        vec2 u = (uv.xy + 1.0) * vec2(2.0, 3.0) * 1.5;
        vec4 o = Texel(cubemap, normalize(uv));
        u += vec2(3.0, 4.0) * daytime;
        float stars = Texel(stars, u).a;
        stars *= max(0.0, sin(3.1415926535898 * (0.5 + daytime) * 2.0));
        o.rgb += stars * stars * 60.0;

        return o;
    }
#endif