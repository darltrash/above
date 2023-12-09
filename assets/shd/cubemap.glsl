uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
varying vec3 uv;

uniform sampler2D perlin;
uniform sampler2D stars;
uniform float daytime;

#define PI 3.1415926535898

#ifdef VERTEX
	vec4 position(mat4 _, vec4 vertex) { 
        uv = (model * vertex).xyz;
        return projection * view * model * vertex; 
    }
#endif

#ifdef PIXEL
    uniform samplerCube cubemap;

    float linearstep(float e0, float e1, float x) {
        return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    }

    vec4 effect(vec4 a, Image b, vec2 uvt, vec2 screen_coords) {
        vec4 o = Texel(cubemap, normalize(uv));
        float stars = Texel(stars, uvt * 9.0).a * step(uvt.y, 0.5);
        stars *= max(0.0, sin(PI * (0.5 + daytime) * 2.0));
        float e = linearstep(0.1, 0.3, uvt.y);
        //stars *= e * e;
        o.rgb += stars * 60.0;

        return o;
    }
#endif