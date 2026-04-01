/*{
	"CREDIT": "by mojovideotech",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"generator",
		"Mobius",
		"Spiral"
	],
	"INPUTS": [
	{
		"NAME" : 		"rate",
		"TYPE" : 		"float",
		"DEFAULT" : 	1.0,
		"MIN" : 		-3.0,
		"MAX" : 		3.0
	},
	{
		"NAME" : 		"mx",
		"TYPE" : 		"float",
		"DEFAULT" : 	1.0,
		"MIN" : 		0.0,
		"MAX" : 		1.0
	},
    {
        "NAME" :       "patternScale",
        "TYPE" :       "float",
        "DEFAULT" :    2.0,
        "MIN" :        1.0,
        "MAX" :        10.0
    },
    {
        "NAME" :       "spiralIntensity",
        "TYPE" :       "float",
        "DEFAULT" :    0.9,
        "MIN" :        0.0,
        "MAX" :        1.0
    },
    {
        "NAME" :       "zoomFactor",
        "TYPE" :       "float",
        "DEFAULT" :    0.25,
        "MIN" :        0.1,
        "MAX" :        2.0
    },
    {
        "NAME" :       "colorIntensity",
        "TYPE" :       "float",
        "DEFAULT" :    0.1,
        "MIN" :        0.1,
        "MAX" :        2.0
    },
    {
        "NAME" :       "reflectivity",
        "TYPE" :       "float",
        "DEFAULT" :    0.5,
        "MIN" :        0.1,
        "MAX" :        1.0
    }
    ]
}*/

////////////////////////////////////////////////////////////
// MobiusSpiral1  by mojovideotech
// Optimized for performance and new adjustable parameters
////////////////////////////////////////////////////////////

#define twpi 6.283185307179586  // two pi, 2*pi
#define pi 3.141592653589793    // pi
#define sxpi 18.84955592153876  // six pi, 6*pi

float T = TIME * rate;

vec2 hash22(vec2 p) { 
    float n = sin(dot(p, vec2(41, 289))); 
    return fract(vec2(8, 1) * 262144. * n);
}

float trace(in vec3 ro, in vec3 rd) {
    float b = dot(ro, rd);
    float h = b * b - dot(ro, ro) + 1.;
    if (h < 0.) return -1.;
    return -b - sqrt(h);
}

vec3 scene(vec2 uv) {
    vec2 id = mod(floor(uv), 5. / 2.);
    uv = fract(uv) - .5;
    vec3 ro = vec3(0, 0, -2.4);
    vec3 rd = normalize(vec3(uv, 1.));
    vec3 lp = ro + vec3(cos(T), sin(T), 0) * 2.;
    float t = trace(ro, rd);
    vec3 col = vec3(1, .04, .1) * 0.003 + length(hash22(uv + 7.31)) * .005;

    if (t > 0.) {
        vec3 p = ro + rd * t;
        vec3 n = normalize(p);
        vec3 ld = lp - p;
        float lDist = max(length(ld), 0.001);
        ld /= lDist;
        float diff = max(dot(ld, n), 0.);
        float spec = pow(max(dot(reflect(-ld, n), -rd), 0.), 16. * reflectivity); // Adjusted by reflectivity
        float c = dot(sin(p * 8. - cos(p.zxy * 8. + pi + T)), vec3(.166)) + .5;

        // Reduced redundant calculations
        float cSin = clamp(sin(c * sxpi) * 2., 0., 1.);
        c = sqrt(cSin * .75 + .25);
        vec3 oCol = vec3(c * colorIntensity);  // Adjusted by colorIntensity
        if (id.x > 1.25) oCol *= vec3(1, .04, .1);

        p = reflect(rd, n) * .35;
        float rC = clamp(sin(dot(sin(p * 8. - cos(p.zxy * 8. + pi)), vec3(.166)) + .5) * sxpi * 2., 0., 1.);
        vec3 rCol = vec3(min(rC * 1.5, 1.), pow(rC, 3.), pow(rC, 8.)); // Reduced power
        vec3 sCol = oCol * (diff * diff + .5) + vec3(.1, .8, 9) * spec * 2. + rCol * .05;

        // Simplified attenuation
        sCol *= 1.5 / (1. + lDist * .3);
        float edge = smoothstep(0., .35, max(dot(-rd, n), 0.));
        col = mix(col, min(sCol, 1.), edge);
    }

    return sqrt(clamp(col, 0., 1.));
}

vec2 Mobius(vec2 p, vec2 z1, vec2 z2) {
    z1 = p - z1;
    p -= z2;
    return vec2(dot(z1, p), z1.y * p.x - z1.x * p.y) / dot(p, p);
}

vec2 spiralZoom(vec2 p, vec2 offs, float n, float spiral, float zoom, vec2 phase) {
    p -= offs;
    float a = atan(p.y, p.x) / twpi + T * .03125;
    float d = length(p);
    return vec2(a * n + log(d) * spiral, -log(d) * zoom + a) + phase;
}

float circle(vec2 p) {
    p = fract(p) - .5;
    float d = length(p);
    return smoothstep(0.2, 0.5, 0.5 - d);
}

void main() {
    vec2 uv = (2.0 * gl_FragCoord.xy - RENDERSIZE.xy) / RENDERSIZE.y;
    uv = Mobius(uv, vec2(-.75, 0), vec2(.5, 0));
    uv = spiralZoom(uv, vec2(-.5), 5., pi * spiralIntensity, zoomFactor, vec2(-1, 1) * T * .125);
    vec3 col = vec3(scene(uv * floor(patternScale)) * 0.5);  // Adjusted by patternScale
    col *= vec3(scene(uv * floor(patternScale)));
    col += mix(vec3(circle(uv * floor(patternScale)), 0.0, scene(uv * floor(patternScale))), vec3(scene(uv * floor(patternScale))), 1.0 - mx);
    gl_FragColor = vec4(min(col, 1.), 1);
}
