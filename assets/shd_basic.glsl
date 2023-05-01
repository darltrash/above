uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

varying vec4 cl_position;
varying vec4 vw_position;
varying vec3 vw_normal;

#ifdef VERTEX
    attribute vec3 VertexNormal;

    // EVIL THING!!!! (idk but why but it broke)
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
        vw_normal = (model * vec4(VertexNormal, 1.0)).xyz;

        cl_position = projection * vw_position;

        return cl_position;
    }
#endif

#ifdef PIXEL
    // Lighting!
    #define LIGHT_AMOUNT 16
    uniform vec4 ambient;
    uniform vec3 light_positions[LIGHT_AMOUNT];
    uniform vec4 light_colors[LIGHT_AMOUNT];
    uniform int light_amount;

    uniform float time;
    uniform vec4 clip;

    // Crazy dither thing
    uniform float dither_table[16];

    vec3 tonemap_aces(vec3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    float dither4x4(vec2 position, float brightness) {
        ivec2 p = ivec2(mod(position, 4.0));
        
        float limit = 0.0;
        if (p.x < 8)
            limit = dither_table[p.x + p.y * 4];

        return brightness < limit ? 0.0 : 1.0;
    }

    float diststep(vec3 a, vec3 b, float d) {
        return max(0.0, d-distance(a, b))/d;
    }

    vec4 effect(vec4 color, Image texture, vec2 tuv, vec2 suv) {
        vec4 o = vec4(1.0);
        vec3 normal = normalize(vw_normal);

        // Lighting! (Diffuse + Rim)
        vec4 lighting = ambient;

        for(int i=0; i<light_amount; ++i) { // For each light
            vec3 position = light_positions[i];
            float area = length(light_colors[i].rgb) * light_colors[i].a;
            float power = 1.0;

            // Diffuse (get the pixel more "lit" if it's closer to the light source)
            float dist = diststep(vw_position.xyz, (view * vec4(position, 1.0)).xyz, area);
            power *= dist;
            power *= max(1.0-dot(normalize(vw_position.xyz - position), normal), 0.0);

            // Rim (uhh, this one sucks? idk it barely makes any difference)
            float rim = 1.0-max(dot(normalize(-vw_position.xyz), normalize(mat3(view) * normal)), 0.0); // rim...?
            power += smoothstep(0.6, 1.0, rim) * 0.5 * dist;

            // Now we add our light's color to the light value
            lighting.rgb += normalize(light_colors[i].rgb) * power;
        }

        // This helps us make the models just use a single portion of the 
        // texture, which allows us to make things such as sprites show up :)
        vec2 uv = clip.xy + tuv * clip.zw;

        // Evrathing togetha
        o = Texel(texture, uv) * color * lighting; // color
        
        // If something is very close to the camera, make it transparent!
        o.a *= (1.0 - diststep(vw_position.xyz, vec3(0.0, 0.0, 0.0), 3.0));
        
        // Calculate dithering based on transparency, skip dithered pixels!
        if (dither4x4(love_PixelCoord.xy, o.a) == 0.0)
            discard;

        // Make the rest of the pixels completely solid
        o.a = 1.0;

        // Correct the color 
        return gammaCorrectColor (
            vec4(tonemap_aces(o.rgb), o.a)
        );

        //love_Canvases[1] = vec4(normalize(normal), 1.0); // normals
    }
#endif