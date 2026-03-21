/*{
    "CATEGORIES": [
        "Patterns"
    ],
    "CREDIT": "by rhythmic visions",
    "DESCRIPTION": "",
    "INPUTS": [
        {
            "DEFAULT": 2.0,
            "MAX": 3.0,
            "MIN": 0.0,
            "NAME": "scale",
            "TYPE": "float"
        },
        {
            "NAME": "color",
            "TYPE": "color",
            "DEFAULT": [
                1,
                0.8,
                0,
                1]
        },
        {
            "DEFAULT": 0.3,
            "MAX": 1,
            "MIN": 0,
            "NAME": "x1",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0.25,
            "MAX": 1,
            "MIN": 0,
            "NAME": "x2",
            "TYPE": "float"
        },
        {
            "DEFAULT": 1301,
            "MAX": 3457,
            "MIN": 11,
            "NAME": "seed",
            "TYPE": "float"
        }
    ],
    "ISFVSN": "2"
}
*/


////////////////////////////////////////////////////////////
// AlienInvaders  by mojovideotech
//
// based on :
// shadertoy.com//4s33Rn by movAX13h 
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////



float N11(float p) {
	vec2 p2 = fract(p * vec2(1669.44908, 1663.89351));
	return fract(p2.x * p2.y * seed);
}

float N12(vec2 p2) {
	p2 = fract(p2 * vec2(16.69449, 16.63893));
    p2 += dot(p2.yx, p2.xy + vec2(15.60062, 15.55209));
	return fract(p2.x * p2.y * seed);
}

float invader(vec2 p, float n) {
	p.x = abs(p.x);
	p.y = floor(p.y - 3.0);
    return step(p.x, 3.0) * step(1.0, floor(mod(n/(exp2(floor(p.x+p.x - 3.0*p.y-p.y))),4.0)));
}

void main() {
    vec2 p = isf_FragNormCoord.xy;
    vec2 center = vec2(0.5, 0.5);
    p -= center;
    p *= scale;
    p += center;
    p  *= 10.;


    float r = N12(vec2(floor(x1 * 100.), floor(x2 * 100.)));
    vec2 ip = vec2(-5., -3.) + p;
    float a = invader(ip, 809999.0*r);
    
	gl_FragColor = vec4(vec3(a * color), 1.0);
}
