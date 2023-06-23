#pragma language glsl3
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform float time;

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
        vw_position = view * model * vertex_position;
        vw_position.x += sin(time)*0.1*vertex_position.y;
        vw_position.z += sin(time+2.0)*0.1*vertex_position.y;

        vw_normal = cofactor(view * model) * VertexNormal;

        cl_position = projection * vw_position;

        vx_color = VertexColor;

        return cl_position;
    }
#endif

#ifdef PIXEL
    uniform Image MainTex;

    // Lighting!
    #define LIGHT_AMOUNT 16
    uniform vec4 ambient;
    uniform vec3 light_positions[LIGHT_AMOUNT];
    uniform vec4 light_colors[LIGHT_AMOUNT];
    uniform int light_amount;

    uniform vec3 harmonics[9];
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

    float linearstep(float e0, float e1, float x) {
        return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    }

    // Actual math
    void effect() {
        // Lighting! (Diffuse)
        vec3 normal = normalize(abs(vw_normal));
        vec4 lighting = ambient; //Texel(sky_texture, normal); // vec4(sh(harmonics, normal), 1.0)

        for(int i=0; i<light_amount; ++i) { // For each light
            vec3 position = (view * vec4(light_positions[i], 1.0)).xyz;
            float intensity = sqrt(light_colors[i].a);
            vec3 color = light_colors[i].rgb;

            float dist = length(position - vw_position.xyz);

            float a = 0.5;
            float b = 1.0;
            float falloff = 1.0 / (1.0 + a * dist + b * dist * dist);
            
            vec3 direction = normalize(vw_position.xyz - position);

            float shade = dot(normal, direction);

            // Now we add our light's color to the light value
            lighting.rgb += color * falloff * 3.0;
        }

        // Evrathing togetha
        vec4 o = VaryingColor * lighting;

        // If something is very close to the camera, make it transparent!
        o.a *= min(1.0, length(vw_position.xyz) / 2.5);

        // Calculate dithering based on transparency, skip dithered pixels!
        if (dither4x4(love_PixelCoord.xy, o.a) < 0.5)
            discard;

        vec3 n = normal * 0.5 + 0.5;

        love_Canvases[0] = vec4(o.rgb, 1.0);
        love_Canvases[1] = vec4(n, 1.0);
    }
#endif