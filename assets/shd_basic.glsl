uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

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
        vw_normal = (model * vec4(VertexNormal, 1.0)).xyz;
        vw_texcoord = VertexTexCoord.xy;

        cl_position = projection * vw_position;

        return cl_position;
    }
#endif

#ifdef PIXEL
    #define LIGHT_AMOUNT 16

    uniform Image MainTex;
    uniform vec4 clip;
    uniform vec4 ambient;
    uniform vec3 light_positions[LIGHT_AMOUNT];
    uniform vec4 light_colors[LIGHT_AMOUNT];
    uniform int light_amount;

    uniform float time;
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

    void effect() {
        vec3 normal = normalize(vw_normal);

        // Lighting! (Diffuse + Rim)
        vec4 lighting = ambient;
        for(int i=0; i<light_amount; ++i) {
            vec3 position = light_positions[i];
            float area = length(light_colors[i].rgb) * light_colors[i].a;
            float power = 1.0;

            // Diffuse
            float dist = diststep(vw_position.xyz, (view * vec4(position, 1.0)).xyz, area);
            power *= dist;
            power *= max(1.0-dot(normalize(vw_position.xyz - position), normal), 0.0);

            // Rim
            float rim = 1.0-max(dot(normalize(-vw_position.xyz), normalize(mat3(view) * normal)), 0.0); // rim...?
            power += smoothstep(0.6, 1.0, rim) * 0.5 * dist;

            lighting.rgb += normalize(light_colors[i].rgb) * power;
        }

        // Evrathing togetha
        love_Canvases[0] = Texel(MainTex, clip.xy + vw_texcoord * clip.zw) * VaryingColor * lighting; // color
        
        love_Canvases[0].a *= (1.0 - diststep(vw_position.xyz, vec3(0.0, 0.0, 0.0), 3.0));
        
        if (dither4x4(love_PixelCoord.xy, love_Canvases[0].a) == 0.0)
            discard;

        love_Canvases[0].a = 1.0;
        

        //float fog = 30.0;
        //float fog_mix = max(0.0, fog-distance(vw_position.xyz, vec3(0.0, 0.0, 0.0)))/fog;
        //if (dither4x4(love_PixelCoord.xy, 1.0-fog_mix) == 1.0)
        //    discard;

        // Correct the color
        love_Canvases[0] = gammaCorrectColor (
            vec4(tonemap_aces(love_Canvases[0].rgb), love_Canvases[0].a)
        );

        love_Canvases[1] = vec4(normalize(normal), 1.0); // normals
        
        //float dist = distance(vw_position.xyz, vec3(0.0, 0.0, 0.0));
        //o.a *= getFogFactor(dist);
    }
#endif