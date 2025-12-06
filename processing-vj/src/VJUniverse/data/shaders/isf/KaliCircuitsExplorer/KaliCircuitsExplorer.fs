/*{
  "CREDIT": "by mojovideotech",
  "CATEGORIES": [
    "generator",
    "kali set"
  ],
  "DESCRIPTION": "",
  "INPUTS": [
    {
      "NAME": "center",
      "TYPE": "point2D",
      "DEFAULT": [
        0,
        0
      ],
      "MAX": [
        2,
        2
      ],
      "MIN": [
        -2,
        -2
      ]
    },
    {
      "NAME": "rate",
      "TYPE": "float",
      "DEFAULT": 1,
      "MIN": 0.01,
      "MAX": 3
    },
    {
      "NAME": "loops",
      "TYPE": "float",
      "DEFAULT": 15,
      "MIN": 8,
      "MAX": 24
    },
    {
      "NAME": "intensity",
      "TYPE": "float",
      "DEFAULT": 0.03,
      "MIN": 0.01,
      "MAX": 0.05
    },
    {
      "NAME": "focus",
      "TYPE": "float",
      "DEFAULT": 2.14,
      "MIN": 0.5,
      "MAX": 5
    },
    {
      "NAME": "pulse",
      "TYPE": "float",
      "DEFAULT": 30,
      "MIN": 6,
      "MAX": 60
    },
    {
      "NAME": "glow",
      "TYPE": "float",
      "DEFAULT": 10,
      "MIN": -100,
      "MAX": 100
    },
    {
      "NAME": "zoom",
      "TYPE": "float",
      "DEFAULT": 0.67,
      "MIN": 0.1,
      "MAX": 1
    }
  ],
  "ISFVSN": 2
}*/

////////////////////////////////////////////////////////////////////
// KaliCircuitsExplorer  by mojovideotech
//
// based on :
// shadertoy.com/XlX3Rj  by Kali
//
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////////////

#ifdef GL_ES
precision highp float;
#endif


#define 	pi   	3.141592653 	// pi
	
float S = (101.0 + glow) * intensity;
vec3 color = vec3(0.0);

void formula(vec2 z, float t) 
{
	float M = 0.0;
	float o, ot2, ot=ot2=1000.0;
	float K = floor(loops/4.0)+floor(5.0 * zoom);
	for (int i=0; i<11; i++) {
		z = abs(z) / clamp(dot(z, z), 0.1, 0.5) - t;
		float l = length(z);
		o = min(max(abs(min(z.x, z.y)), -l + 0.25), abs(l - 0.25));
		ot = min(ot, o);
		ot2 = min(l * 0.1, ot2);
		M = max(M, float(i) * (1.0 - abs(sign(ot - o))));
		if (K <= 0.0) break;
		K -= 1.0;
	}
	M += 1.0;
	float w = (intensity * zoom) * M;
	float circ = pow(max(0.0, w - ot2) / w, 6.0);
	S += max(pow(max(0.0, w - ot) / w, 0.25), circ);
	vec3 col = normalize(0.1 + vec4(0.45, 0.75, M * 0.1, 1.0).rgb);
	color += col * (0.4 + mod(M / 9.0 - t * pulse + ot2 * 2.0, 1.0));
	color += vec3(1.0, 0.7, 0.3) * circ * (10.0 - M) * 3.0;
}


void main()
{
	float R = 0.0;
	float N = TIME * 0.01 * rate;
	float T = 2.0 * rate;
	if (N > 6.0 * rate) { 
		R += 1.0;
		N -= (R * 8.0 * rate);
	}
	if (N < 4.0 * rate) T += N;
	else  T = 8.0 * rate - N;
	float Z = (1.05-zoom);
	vec2 pos = gl_FragCoord.xy / RENDERSIZE.xy - 0.5;
	pos.x *= RENDERSIZE.x/RENDERSIZE.y;
	vec2 uv = pos + center;
	float sph = length(uv)*0.1; 
	sph = sqrt(1.0 - sph * sph) * 2.0 ;
	float a = T * pi;
	float b = a + T;
	float c = cos(a) + sin(b);
	uv *= mat2(cos(b), sin(b), -sin(b), cos(b));
	uv *= mat2(cos(a),-sin(a), sin(a),cos(a));
	uv -= vec2(sin(c), cos(c)) / pi;
	uv *= Z;
	float pix = 0.5 / RENDERSIZE.x * Z / sph;
	float dof = (zoom * focus) + (T * 0.25);
	float L = floor(loops);
	for (int aa=0; aa<24; aa++) {
		vec2 aauv = floor(vec2(float(aa) / 6.0, mod(float(aa), 6.0)));
		formula(uv + aauv * pix * dof, T);
		if (L <= 0.0) break;
		L -= 1.0;
	}
	S /= floor(loops); 
	color /= floor(loops);
	vec3 colo = mix(vec3(0.15), color, S) * (1.0 - length(pos));	
	colo *=vec3(1.2, 1.1, 1.0);
	gl_FragColor = sqrt(max(vec4(colo, 1.0), 0.0) -0.2);
}
