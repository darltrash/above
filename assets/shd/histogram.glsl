// Ported from Manta's tech

uniform vec4 u_adaptation_params = vec4(0.016, 10.1, 0.025, 15.0); 
#define u_dt u_adaptation_params.x 
#define u_adaptation_speed u_adaptation_params.y 
#define u_min_ev u_adaptation_params.z 
#define u_max_ev u_adaptation_params.w 
 
const float offset = -1.0; 
const float bias = 1.5; 
const float limit_boost = 1.05; 
const float limit_reduce = 0.2; 

#ifdef VERTEX
	vec4 position(mat4 mvp, vec4 vertex) { return mvp * vertex; }
#endif

#ifdef PIXEL
    uniform float last_luma;
    uniform float target_luma;

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
        float expo = imageLoad(s_input, ivec2(0, 0)).x * bias + offset; 
        float target_luma = clamp(exp2(-expo), limit_reduce, limit_boost); 
        
        float delta_luma = target_luma - last_luma; 
        float adapted_luma = last_luma + delta_luma * (1.0 - exp2(-u_dt * u_adaptation_speed)); 

        return adapted_luma;
    }
#endif