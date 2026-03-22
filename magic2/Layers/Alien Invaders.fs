/*{
    "CATEGORIES": [
        "Patterns"
    ],
    "CREDIT": "by mojovideotech",
    "DESCRIPTION": "",
    "INPUTS": [
        {
            "DEFAULT": 0.9,
            "MAX": 1,
            "MIN": 0.5,
            "NAME": "scale",
            "TYPE": "float"
        },
        {
            "DEFAULT": 1.5,
            "MAX": 3,
            "MIN": 0.5,
            "NAME": "rate",
            "TYPE": "float"
        },
        {
            "DEFAULT": 5,
            "MAX": 100,
            "MIN": -100,
            "NAME": "scroll",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0.3,
            "MAX": 1,
            "MIN": 0,
            "NAME": "R",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0.25,
            "MAX": 1,
            "MIN": 0,
            "NAME": "G",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0.4,
            "MAX": 1,
            "MIN": 0,
            "NAME": "B",
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



vec3 color = vec3(R, G, B);
float T = TIME * rate;

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

float ring(vec2 uv, float rnd) {
    float t = 0.2*(T+0.2*rnd);
    float i = floor(t*0.5);
    vec2 pos = 2.0*vec2(N11(i*0.123), N11(i*2.371))-1.0;
	return smoothstep(0.5, -0.5, abs(length(uv-pos)-mod(t,2.0)));
}

void main() {
	vec2 p = gl_FragCoord.xy*(1.0125-scale);
	vec2 uv = p / RENDERSIZE.xy - 0.5;
    p.y += scroll*TIME;
    float r = N12(floor(p*0.1));
    vec2 ip = mod(p,10.0)-6.0;
    float a = -0.3*smoothstep(0.1, 0.8, length(uv)) + 
        invader(ip, 809999.0*r) * (0.06 + 0.8*ring(uv,r) + max(0.0, 0.2*sin(10.0*r*T)));
    
	gl_FragColor = vec4(sqrt(abs(max(0.5-(color-a),-0.5))), 1.0);
}
