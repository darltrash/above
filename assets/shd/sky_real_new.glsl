#pragma language glsl3

//uniform sampler2D night_sky : source_color, filter_linear_mipmap;

uniform float luminance = 1.05; // formerly uniform
const float night_luminance = 1.125;
uniform float turbidity = 8.0; // formerly uniform
uniform float reileigh = 1.25; // formerly uniform
uniform float mieCoefficient = 0.005;
uniform float mieDirectionalG = 0.8;
uniform float light_power = 0.5;
uniform float light_power_adjust = 4.0;
uniform float exposure = -4.0;
uniform float ambient_boost = 0.0;

/*
uniform sampler2D clouds_texture: filter_linear_mipmap;
uniform sampler2D clouds_distort_texture: filter_linear_mipmap;
uniform sampler2D clouds_noise_texture: filter_linear_mipmap;
uniform vec3 clouds_main_color: source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 clouds_edge_color: source_color = vec3(1.0, 1.0, 1.0);
uniform float clouds_speed: hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float clouds_scale: hint_range(25.0, 100.0, 0.1) = 25.0;
uniform float clouds_cutoff: hint_range(0.0, 1.0, 0.01) = 0.17;
uniform float clouds_fuzziness: hint_range(0.0, 1.0, 0.01) = 0.79;
uniform float cloud_height: hint_range(250.0, 1000.0) = 1000.0;
uniform float cloud_step: hint_range(0.0, 2.0) = 0.5;
uniform float cloud_parallax: hint_range(0.0, 1.0) = 1.0;
uniform int cloud_layers: hint_range(1, 32) = 6;
*/

#define fma(a, b, c) ((a) * (b) * (c))

uniform vec3 LIGHT0_COLOR = vec3(1.0);
uniform vec3 LIGHT0_DIRECTION = vec3(0.0, 1.0, 0.0);
uniform bool LIGHT0_ENABLED = true;
uniform float LIGHT0_ENERGY = 100.0;
uniform vec3 LIGHT1_DIRECTION = vec3(0.0, -1.0, 0.0);
uniform float TIME = 0.0;

uniform bool AT_CUBEMAP_PASS = false;

// constants for atmospheric scattering
const float e = 2.71828182845904523536028747135266249775724709369995957;
const float PI = 3.141592653589793238462643383279502884197169;
const float TAU = PI * 2;

// refractive index of air
const float n = 1.0003;

// number of molecules per unit volume for air at 288.15K and 1013mb (sea level -45 celsius)
const float N = 2.545E25;

// depolatization factor for standard air
const float pn = 0.035;

// wavelength of used primaries, according to preetham
const vec3 kLambda = vec3(680E-9, 550E-9, 450E-9);

// mie stuff
// K coefficient for the primaries
const vec3 kK = vec3(0.686, 0.678, 0.666);
const float v = 4.0;

// optical length at zenith for molecules
const float rayleighZenithLength = 8.4E3;
const float mieZenithLength = 1.25E3;
const vec3 up = vec3(0.0, 1.0, 0.0);

const float EE = 1000.0;
// increased size so it can bloom
const float sunAngularDiameterCos = 0.99996192306417 * 0.999925;//*0.9995; // probably correct size, maybe

// earth shadow hack
const float steepness = 1.5;

vec3 totalRayleigh(vec3 lambda) {
	return (8.0 * pow(PI, 3.0) * pow(pow(n, 2.0) - 1.0, 2.0) * (6.0 + 3.0 * pn)) / (3.0 * N * pow(lambda, vec3(4.0)) * (6.0 - 7.0 * pn));
}

// see http://blenderartists.org/forum/showthread.php?321110-Shaders-and-Skybox-madness
// A simplied version of the total Rayleigh scattering to works on browsers that use ANGLE
vec3 simplifiedRayleigh() {
	return 0.00054532832366 / vec3(94.0, 40.0, 18.0);
}

float rayleighPhase(float cosTheta) {
	return (3.0 / (16.0*PI)) * (1.0 + pow(cosTheta, 2.0));
}

vec3 totalMie(vec3 lambda, vec3 K, float T) {
	float c = (0.2 * T ) * 10E-18;
	return 0.434 * c * PI * pow(TAU / lambda, vec3(v - 2.0)) * K;
}

float hgPhase(float cosTheta, float g) {
	return (1.0 / (4.0*PI)) * ((1.0 - pow(g, 2.0)) / pow(1.0 - 2.0*g*cosTheta + pow(g, 2.0), 1.5));
}

float sunIntensity(float zenithAngleCos) {
	// See https://github.com/mrdoob/three.js/issues/8382
	float cutoffAngle = PI/1.95;
	return EE * max(0.0, 1.0 - pow(e, -((cutoffAngle - acos(zenithAngleCos))/steepness)));
}

vec3 generate_sky(vec3 in_dir, vec3 sun_dir, vec3 moon_dir) {
	// several of these could be precomputed (not view dependent) outside of this shader (cpu or vs)
	float sunfade = 1.0-clamp(1.0-exp((sun_dir.y/450000.0)),0.0,1.0);
	float reileighCoefficient = reileigh - (1.0 * (1.0-sunfade));
	vec3 sunDirection = normalize(sun_dir.xyz);
	float sunE = sunIntensity(dot(sunDirection, up));

	// extinction (absorbtion + out scattering)
	// rayleigh coefficients
	vec3 betaR = simplifiedRayleigh() * reileighCoefficient;

	// mie coefficients
	vec3 betaM = totalMie(kLambda, kK, turbidity) * mieCoefficient;

	// optical length
	// cutoff angle at 90 to avoid singularity in next formula.
	float zenithAngle = acos(max(0.0, dot(up, normalize(in_dir.xyz))));
	float sR = rayleighZenithLength / (cos(zenithAngle) + 0.15 * pow(93.885 - ((zenithAngle * 180.0) / PI), -1.253));
	float sM = mieZenithLength / (cos(zenithAngle) + 0.15 * pow(93.885 - ((zenithAngle * 180.0) / PI), -1.253));

	// combined extinction factor
	vec3 Fex = exp(-(betaR * sR + betaM * sM));

	// in scattering
	float cosTheta = dot(normalize(in_dir.xyz), sunDirection);

	float rPhase = rayleighPhase(cosTheta*0.5+0.5);
	vec3 betaRTheta = betaR * rPhase;

	float mPhase = hgPhase(cosTheta, mieDirectionalG);
	vec3 betaMTheta = betaM * mPhase;

	vec3 Lin = pow(sunE * ((betaRTheta + betaMTheta) / (betaR + betaM)) * (1.0 - Fex),vec3(1.5));
	float sun_dot_up = dot(up, sunDirection);

	Lin *= mix(vec3(1.0),pow(sunE * ((betaRTheta + betaMTheta) / (betaR + betaM)) * Fex,vec3(1.0/2.0)),clamp(pow(1.0-sun_dot_up,5.0),0.0,1.0));

	// night sky
	vec3 direction = normalize(in_dir.xyz);
	float theta = acos(direction.y); // elevation --> y-axis, [-pi/2, pi/2]
	float phi = atan(direction.z/direction.x); // azimuth --> x-axis [-pi/2, pi/2]
	//vec3 L0 = vec3(0.1) * Fex;
	vec3 L0 = Fex;

	// composition + solar disc
	float moondisk = 0.0;
	float moonCosTheta = dot(normalize(in_dir.xyz), moon_dir);
	if (!AT_CUBEMAP_PASS) {
		float sundisk = smoothstep(sunAngularDiameterCos,sunAngularDiameterCos+0.001,cosTheta);
		vec3 halo = kK * kLambda * pow(max(0.0, cosTheta*cosTheta*cosTheta), 100.0) * (0.5+0.5*vec3(4.0, 10.0, 17.0)) * sunE * 0.001;
		vec3 halo2 = kK * kLambda * pow(max(0.0, cosTheta), 2.0) * (0.5+0.5*vec3(4.0, 10.0, 17.0)) / max(1.0, sunE) * EE * 0.05;
		L0 += (sunE * 19000.0 * LIGHT0_ENERGY * Fex)*(sundisk+halo+halo2);

		moondisk = smoothstep(sunAngularDiameterCos,sunAngularDiameterCos+0.0005,moonCosTheta);
	}
	float mhalo = pow(max(0.0, moonCosTheta), 2.0) * 0.0001;
	L0 += (moondisk + mhalo) * 7500.0;

	vec3 texColor = (Lin+L0);
	texColor *= 0.06 * light_power_adjust;
	texColor += vec3(0.0,0.001,0.0025)*0.3;

	float night_lum = mix(1.125, luminance, max(0.0, dot(sunDirection, up)));
	vec3 color = log2(2.0/pow(night_lum,4.0))*texColor;

	vec3 retColor = pow(color,vec3(1.0/(1.2+(1.2*sunfade))));
	retColor = mix(retColor * 0.75, retColor, clamp(dot(direction, up) * 0.5 + 0.5, 0.0, 1.0));
	//retColor *= exp2(0.25); // why?
	retColor *= exp2(exposure);
	retColor = pow(retColor, vec3(1.5));
	if (LIGHT0_ENABLED) {
		retColor *= exp2(LIGHT0_ENERGY * light_power);
	}
	if (AT_CUBEMAP_PASS) {
		retColor *= exp2(ambient_boost);
	}
	return retColor;
}

float dither17(vec2 pos, float index_mod_4) {
	return fract(dot(vec3(pos.xy, index_mod_4), vec3(2.0, 7.0, 23.0) / 17.0));
}

vec4 ray_plane(vec3 rp, vec3 rd, vec3 pp, vec3 pd) {
	float t = dot(pp - rp, pd) / dot(pd, rd);
	return mix(
		vec4(0.0, 0.0, 0.0, -1.0), // clip
		vec4(rp + rd * t, 1.0),
		step(t, 0.0)
	);
}

vec4 cubic(float _v) {
	vec4 nn = vec4(1.0, 2.0, 3.0, 4.0) - _v;
	vec4 s = nn * nn * nn;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0/6.0);
}

vec4 textureBicubic(sampler2D sampler, vec2 texCoords) {
	vec2 texSize = vec2(textureSize(sampler, 0));
	vec2 invTexSize = 1.0 / texSize;

	texCoords = texCoords * texSize - 0.5;

	vec2 fxy = fract(texCoords);
	texCoords -= fxy;

	vec4 xcubic = cubic(fxy.x);
	vec4 ycubic = cubic(fxy.y);

	vec4 c = texCoords.xxyy + vec2(-0.5, +1.5).xyxy;

	vec4 s = vec4(xcubic.xz + xcubic.yw, ycubic.xz + ycubic.yw);
	vec4 offset = c + vec4(xcubic.yw, ycubic.yw) / s;

	offset *= invTexSize.xxyy;

	vec4 sample0 = textureLod(sampler, offset.xz, 0.0);
	vec4 sample1 = textureLod(sampler, offset.yz, 0.0);
	vec4 sample2 = textureLod(sampler, offset.xw, 0.0);
	vec4 sample3 = textureLod(sampler, offset.yw, 0.0);

	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);

	return mix(
		mix(sample3, sample2, sx), mix(sample1, sample0, sx),
		sy
	);
}

//vec3 generate_clouds(vec3 eye_dir) {
//	float plane_scale = 0.00045;
//	float cloud_time_offset = TIME * clouds_speed * 0.01;
//	float rcp_cloud_scale = 1.0 / clouds_scale;
//	vec2 inf_uv = eye_dir.xz / eye_dir.y;
//	vec3 clouds = vec3(0.0);
//	for (int i = 0; i < cloud_layers; i++) {
//		float cloud_offset = float(i) * cloud_step;
//		vec3 cloud_pos = vec3(0.0, cloud_height + cloud_offset, 0.0);
//		vec4 hit = ray_plane(POSITION, -eye_dir, cloud_pos, vec3(0.0, -1.0, 0.0));
//		if (hit.w < 0.0) {
//			continue;
//		}
//		vec2 sky_uv = mix(inf_uv, hit.xz * plane_scale, cloud_parallax);
//		float cloud_base1 = texture(clouds_texture, (sky_uv + cloud_time_offset) * rcp_cloud_scale * 2.0).r * 0.5;
//		// bicubic lookup has dramatically higher quality here, and the cost seems OK
//		float cloud_base2 = cloud_base1 + textureHQ(clouds_texture, (sky_uv + cloud_time_offset * 1.451) * rcp_cloud_scale * 2.45 + cloud_time_offset * 0.2).r * 0.5;
//		float noise1 = textureHQ(clouds_distort_texture, (sky_uv + cloud_base2 + (cloud_time_offset * 0.75)) * rcp_cloud_scale).r;
//		float noise2 = textureHQ(clouds_noise_texture, (sky_uv + noise1 + (cloud_time_offset * 0.25)) * rcp_cloud_scale).r;
//		float cloud_mix = clamp(noise1 * noise2, 0.0, 1.0) * clamp(0.75 - pow(eye_dir.y, 0.75) * 0.25, 0.0, 1.0);
//		float cloud_edge = clamp(smoothstep(clouds_cutoff, clouds_cutoff + clouds_fuzziness, cloud_mix), 0.0, 1.0);
//		clouds += mix(clouds_edge_color * LIGHT0_COLOR, clouds_main_color, cloud_edge) * cloud_edge;
//	}
//	return clouds / float(cloud_layers) * step(0.0, eye_dir.y);
//}

varying vec3 vw_position;

#ifdef VERTEX
    uniform mat4 inverse_view_proj;

    vec4 position(mat4 mvp, vec4 vertex) { 
        vec4 o = vec4(vertex.xy*vec2(-1.0, 1.0), 2.0 * step(0.5, vertex.z) - 1.0, 1.0);
        vw_position = mat3(inverse_view_proj) * vec3(vertex.x, vertex.y, o.z);

        return o;
    }
#endif

#ifdef PIXEL
vec4 effect(vec4 _, Image tex, vec2 uv, vec2 screen_coords) {
	//vec2 star_uv = EYEDIR.xz / EYEDIR.y;
    vec3 EYEDIR = normalize(-vw_position);
	float sky_mix = smoothstep(-0.1, 0.5, dot(EYEDIR, vec3(0.0, 1.0, 0.0)));
    vec3 COLOR = vec3(0.0);

	COLOR = generate_sky(EYEDIR, LIGHT0_DIRECTION, LIGHT1_DIRECTION);
	COLOR += length(COLOR) * fma(dither17(love_PixelCoord.xy, 0), 2.0, -1.0) * 0.01;
	//vec3 clouds = generate_clouds(EYEDIR) * mix(vec3(length(COLOR)), COLOR, 0.25) * 3.5;
	//COLOR += clouds;

	if (!AT_CUBEMAP_PASS) {
		//COLOR += texture(night_sky, SKY_COORDS).rgb * sky_mix * 0.2 * smoothstep(0.1, -0.4, LIGHT0_DIRECTION.y);
	}

    return vec4(COLOR, 1.0) * 10.0;
}
#endif