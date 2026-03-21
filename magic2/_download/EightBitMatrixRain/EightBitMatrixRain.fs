/*{
	"CREDIT": "by mojovideotech",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"generator",
		"matrix"
	],
	"INPUTS" : [
    {
        "NAME" :      "scale",
        "TYPE" :      "float",
        "DEFAULT" :   60.0,
        "MIN" :       4.0,
        "MAX" :       100.0
    },
    {
        "NAME" :      "rate",
        "TYPE" :      "float",
        "DEFAULT" :   16.0,
        "MIN" :       1.0,
        "MAX" :       60.0
    },
    {
        "NAME" :      "seed1",
        "TYPE" :      "float",
        "DEFAULT" :   13,
        "MIN" :       3,
        "MAX" :       34
    },
    {
        "NAME" :      "seed2",
        "TYPE" :      "float",
        "DEFAULT" :   89,
        "MIN" :       55,
        "MAX" :       233
    },
    {
        "NAME" :      "seed3",
        "TYPE" :      "float",
        "DEFAULT" :   377,
        "MIN" :       144,
        "MAX" :       610
    },
    {
        "NAME" :      "R",
        "TYPE" :      "float",
        "DEFAULT" :   0.2,
        "MIN" :       0.0,
        "MAX" :       1.0
    },
    {
        "NAME" :      "G",
        "TYPE" :      "float",
        "DEFAULT" :   0.5,
        "MIN" :       0.0,
        "MAX" :       1.0
    },
    {
        "NAME" :      "B",
        "TYPE" :      "float",
        "DEFAULT" :   0.1,
        "MIN" :       0.0,
        "MAX" :       1.0
    }, 
    {
        "NAME" :      "gamma",
        "TYPE" :      "float",
        "DEFAULT" :   2.2,
        "MIN" :       0.25,
        "MAX" :       3.5
    }
  ],
   "ISFVSN" : 2.0
}
*/


////////////////////////////////////////////////////////////////////
// EightBitMatrixRain  by mojovideotech
//
// based on :
// thebookofshaders.com/\08   by patricio gonzalez vivov
//
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////////////



float T = mod(TIME,300.0 - scale);

float N11(float p) { return fract(sin(p) * 43349.4437); }

float N12(vec2 p2) { return fract(sin(dot(p2, vec2(seed2, seed3 - seed1))) * 28657.1597); }

float glyph(in vec2 o,in vec2 i) {
    vec2 m = vec2(0.2, 0.05);
    vec2 b = step(m, i) * step(m, 1.0 - i);
    return step(0.5, N12(o * seed1 + floor(i * 5.0))) * b.x * b.y;
}

vec3 matrix(in vec2 st) {
	T *= rate;
    float r = floor(101.0 - scale);
    vec2 ip = floor(st * r) + vec2(1.0, 0.0);
    ip += vec2(0.0, floor(T * N11(ip.x)));
    vec2 fp = fract(st * r);
    vec2 c = (0.5 - fp);
    float g = (1.0 - dot(c, c) * 3.0) * 2.0;
    return vec3(glyph(ip, fp) * N12(ip.xy) * g);
}

void main()
{
	vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
    uv.y *= RENDERSIZE.y / RENDERSIZE.x;
    vec3 col = matrix(uv) * vec3(R, G, B);
    col = pow(gamma * col, vec3(1.0)); 

    gl_FragColor = sqrt(vec4(col, 1.0));
}
