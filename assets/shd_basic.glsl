uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

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

    uniform float time;
    uniform vec4 clip;
    uniform float translucent; // useful for displaying flat things

    // Crazy dither thing
    uniform float dither_table[4*4];

    float dither4x4(vec2 position, float brightness) {
        ivec2 p = ivec2(mod(position, 4.0));
        
        float limit = mix(0.0, dither_table[p.x + p.y * 4], step(float(p.x), 8.0));

        return step(limit, brightness);
    }

    float linearstep(float e0, float e1, float x) {
        return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    }

    // Actual math
    void effect() {
        // Lighting! (Diffuse + Rim)
        vec4 lighting = ambient;
        vec3 normal = normalize(vw_normal);

        for(int i=0; i<light_amount; ++i) { // For each light
            vec3 position = (view * vec4(light_positions[i], 1.0)).xyz;
            float intensity = sqrt(light_colors[i].a);
            vec4 color = vec4(normalize(light_colors[i].rgb) * intensity, intensity);

            float dist = max(0.001, length(position - vw_position.xyz));
            float power = sqr(linearstep(color.w, 0.0, dist));
            
            float shade = dot(normalize(vw_position.xyz - position), normal);
            power *= mix(max(0.0, 1.0 - shade), 1, translucent);

            // Now we add our light's color to the light value
            lighting.rgb += normalize(color.rgb) * power;
        }

        // This helps us make the models just use a single portion of the 
        // texture, which allows us to make things such as sprites show up :)
        vec2 uv = clip.xy + VaryingTexCoord.xy * clip.zw;

        // Evrathing togetha
        vec4 o = Texel(MainTex, uv) * VaryingColor * lighting; // color
        
        // If something is very close to the camera, make it transparent!
        o.a *= min(1.0, length(vw_position.xyz) / 3.0);
        
        // Calculate dithering based on transparency, skip dithered pixels!
        if (dither4x4(love_PixelCoord.xy, o.a) < 0.5)
            discard;

        vec3 n = mix(normal, abs(normal), translucent) * 0.5 + 0.5;

        love_Canvases[0] = vec4(o.rgb, 1.0);
        love_Canvases[1] = vec4(n, 1.0);
    }
#endif