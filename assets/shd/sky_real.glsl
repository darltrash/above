#pragma language glsl3
// Stolen from https://github.com/shakesoda/tinyfx/blob/master/examples/02-sky.glsl

varying vec3 vw_position;

#ifdef VERTEX
    uniform mat4 inverse_view_proj;

    vec4 position(mat4 mvp, vec4 vertex) { 
        vec4 o = vec4(vertex.xy * vec2(-1.0, 1.0), 2.0 * step(0.5, vertex.z) - 1.0, 1.0);
        vw_position = mat3(inverse_view_proj) * vec3(vertex.x, vertex.y, o.z);
        return o;
    }
#endif

#ifdef PIXEL
    precision highp float;

    uniform vec4 sun_params;

    const vec3 luma = vec3(0.299, 0.587, 0.114);
    const vec3 cameraPos = vec3(0.0, 0.0, 0.0);
    const float luminance = 1.05; // formerly uniform
    const float turbidity = 8.0; // formerly uniform
    const float reileigh = 1.25; // formerly uniform
    const float mieCoefficient = 0.005;
    const float mieDirectionalG = 0.8;

    // constants for atmospheric scattering
    const float e = 2.71828182845904523536028747135266249775724709369995957;
    const float pi = 3.141592653589793238462643383279502884197169;

    // refractive index of air
    const float n = 1.0003;

    // number of molecules per unit volume for air at 288.15K and 1013mb (sea level -45 celsius)
    const float N = 2.545E25;

    // depolatization factor for standard air
    const float pn = 0.035;

    // wavelength of used primaries, according to preetham
    const vec3 lambda = vec3(680E-9, 550E-9, 450E-9);

    // mie stuff
    // K coefficient for the primaries
    const vec3 K = vec3(0.686, 0.678, 0.666);
    const float v = 4.0;

    // optical length at zenith for molecules
    const float rayleighZenithLength = 8.4E3;
    const float mieZenithLength = 1.25E3;
    const vec3 up = vec3(0.0, 1.0, 0.0);

    const float EE = 1000.0;
    const float sunAngularDiameterCos = 0.99996192306417*0.9995; // probably correct size, maybe

    // earth shadow hack
    const float steepness = 1.5;

    vec3 tonemap_aces(vec3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    vec3 totalRayleigh(vec3 lambda) {
        return (8.0 * pow(pi, 3.0) * pow(pow(n, 2.0) - 1.0, 2.0) * (6.0 + 3.0 * pn)) / (3.0 * N * pow(lambda, vec3(4.0)) * (6.0 - 7.0 * pn));
    }

    // see http://blenderartists.org/forum/showthread.php?321110-Shaders-and-Skybox-madness
    // A simplied version of the total Rayleigh scattering to works on browsers that use ANGLE
    vec3 simplifiedRayleigh() {
        return 0.00054532832366 / vec3(94.0, 40.0, 18.0);
    }

    float rayleighPhase(float cosTheta) {
        return (3.0 / (16.0*pi)) * (1.0 + pow(cosTheta, 2.0));
    }

    vec3 totalMie(vec3 lambda, vec3 K, float T) {
        float c = (0.2 * T ) * 10E-18;
        return 0.434 * c * pi * pow((2.0 * pi) / lambda, vec3(v - 2.0)) * K;
    }

    float hgPhase(float cosTheta, float g) {
        return (1.0 / (4.0*pi)) * ((1.0 - pow(g, 2.0)) / pow(1.0 - 2.0*g*cosTheta + pow(g, 2.0), 1.5));
    }

    float sunIntensity(float zenithAngleCos) {
        // See https://github.com/mrdoob/three.js/issues/8382
        float cutoffAngle = pi/1.95;
        return EE * max(0.0, 1.0 - pow(e, -((cutoffAngle - acos(zenithAngleCos))/steepness)));
    }

    vec4 effect(vec4 _, Image tex, vec2 uv, vec2 screen_coords) {
        float sunfade = 1.0-clamp(1.0-exp((sun_params.y/450000.0)),0.0,1.0);
        float reileighCoefficient = reileigh - (1.0* (1.0-sunfade));
        vec3 sunDirection = normalize(sun_params.xyz);
        float sunE = sunIntensity(dot(sunDirection, up));

        // extinction (absorbtion + out scattering)
        // rayleigh coefficients
        vec3 betaR = totalRayleigh(lambda) * reileighCoefficient;

        // mie coefficients
        vec3 betaM = totalMie(lambda, K, turbidity) * mieCoefficient;

        // optical length
        // cutoff angle at 90 to avoid singularity in next formula.
        float zenithAngle = acos(max(0.0, dot(up, normalize(vw_position.xyz - cameraPos))));
        float sR = rayleighZenithLength / (cos(zenithAngle) + 0.15 * pow(93.885 - ((zenithAngle * 180.0) / pi), -1.253));
        float sM = mieZenithLength / (cos(zenithAngle) + 0.15 * pow(93.885 - ((zenithAngle * 180.0) / pi), -1.253));

        // combined extinction factor
        vec3 Fex = exp(-(betaR * sR + betaM * sM));

        // in scattering
        float cosTheta = dot(normalize(vw_position.xyz), sunDirection);

        float rPhase = rayleighPhase(cosTheta*0.5+0.5);
        vec3 betaRTheta = betaR * rPhase;

        float mPhase = hgPhase(cosTheta, mieDirectionalG);
        vec3 betaMTheta = betaM * mPhase;

        vec3 Lin = pow(sunE * ((betaRTheta + betaMTheta) / (betaR + betaM)) * (1.0 - Fex),vec3(1.5));
        float sun_dot_up = dot(up, sunDirection);

        Lin *= mix(vec3(1.0),pow(sunE * ((betaRTheta + betaMTheta) / (betaR + betaM)) * Fex,vec3(1.0/2.0)),clamp(pow(1.0-sun_dot_up,5.0),0.0,1.0));

        // night sky
        vec3 direction = normalize(vw_position.xyz);
        float theta = acos(direction.y); // elevation --> y-axis, [-pi/2, pi/2]
        float phi = atan(direction.z/direction.x); // azimuth --> x-axis [-pi/2, pi/2]
        vec3 L0 = vec3(0.1) * Fex;

        // composition + solar disc
        float sundisk = smoothstep(sunAngularDiameterCos,sunAngularDiameterCos+0.0001,cosTheta);
        L0 += (sunE * 19000.0 * Fex)*sundisk;

        vec3 texColor = (Lin+L0);
        texColor *= 0.04;
        texColor += vec3(0.0,0.001,0.0025)*0.3;

        vec3 color = log2(2.0/pow(luminance,4.0))*texColor;

        vec3 retColor = pow(color, vec3(1.0/(1.2+(1.2*sunfade))));

        retColor = mix(retColor * 0.75, retColor, clamp(dot(direction, up) * 0.5 + 0.5, 0.0, 1.0));
        retColor *= retColor;

        return vec4(retColor, 1.0) * 8.0;
    }
#endif