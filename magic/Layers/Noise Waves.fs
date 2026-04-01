/*{
	"CREDIT": "by rhythmic visions",
  "CATEGORIES" : [
  	"generator",
    "Perlin Noise",
    "noise",
    "procedural"
  ],
  "INPUTS" : [
	{
		"NAME" : 		"scale",
		"TYPE" : 		"float",
		"DEFAULT" : 	0.02,
		"MIN" : 		0.0001,
		"MAX" : 		0.1
	},
	{
		"NAME" : 		"rate",
		"TYPE" : 		"float",
		"DEFAULT" : 	1.0,
		"MIN" : 		0.001,
		"MAX" : 		3.0
	},
	{
     	"NAME" :		"seed",
     	"TYPE" : 		"float",
     	"DEFAULT" :		13,
     	"MIN" : 		8,
     	"MAX" :			233
	},

	{
		"NAME" : 		"freq",
		"TYPE" : 		"float",
		"DEFAULT" : 	47.0,
		"MIN" : 		3.0,
		"MAX" : 		73.0
	},
	{
		"NAME" : 		"freq3",
		"TYPE" : 		"float",
		"DEFAULT" : 	3.0,
		"MIN" : 		1.0,
		"MAX" : 		11.0
	},
	{
      	"NAME" : 		"colormod",
      	"TYPE" : 		"float",
      	"DEFAULT" :		0.99,
      	"MIN" : 		0.0,
      	"MAX" : 		1.0
    },
    {
      	"NAME" :		"offset",
      	"TYPE":			"float",
      	"DEFAULT" :		0.0,
      	"MIN" :			0.0,
      	"MAX" :			1.0
    },
    {
      	"NAME" :		"offset1",
      	"TYPE":			"float",
      	"DEFAULT" :		0.4,
      	"MIN" :			0.1,
      	"MAX" :			1.0
    },
	{
  		"NAME": 		"flip",
      	"TYPE": 		"bool",
      	"DEFAULT": 		"FALSE"
    },
    {
      	"NAME": 		"invert",
      	"TYPE": 		"bool",
      	"DEFAULT": 		"FALSE"
    }
  ],
  "DESCRIPTION" : "based on http:\/\/glslsandbox.com\/e#39961.5"
}
*/

////////////////////////////////////////////////////////////
// Noise Waves, modified version of
// PNoiseWaveFactory  by mojovideotech
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////


float fade(float t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }

vec2 smooth(vec2 x) { return vec2( fade(x.x), fade(x.y)); }

vec2 hash(vec2 co) {
    float m = dot(co, vec2(seed, 53.));
    return fract( vec2( sin(m), cos(m)) * 2933227.) * 2.0 - 1.0;
}

float pNoise(vec2 uv) {
    vec2 PT  = floor(uv);
    vec2 pt  = fract(uv);
    vec2 mmpt = smooth(pt);
    vec4 grads = vec4(dot(hash(PT + vec2(0.0, 1.0)), pt-vec2(0.0, 1.0)),   
    				dot(hash(PT + vec2(1.0, 1.0)), pt-vec2(1.0, 1.0)),
        			dot(hash(PT + vec2(0.0, 0.0)), pt-vec2(0.0, 0.0)),   
        			dot(hash(PT + vec2(1.0, 0.0)), pt-vec2(1.0, 0.0)));
    return 5.*mix (mix (grads.z, grads.w, mmpt.x), mix (grads.x, grads.y, mmpt.x), mmpt.y);
}

float fbm(vec2 uv) {
    float N = TIME * rate;
    N += 1.0000*pNoise(10.0*uv);
    N += 0.50000*pNoise(20.0*uv);
    N += 0.25000*pNoise(40.0*uv);
    N += 0.12500*pNoise(80.0*uv);
    N += 0.06250*pNoise(160.0*uv);
    N += 0.03125*pNoise(320.0*uv);
    return N;
}

void main() {
    vec2 p = (gl_FragCoord.xy - 0.5 * RENDERSIZE.xy) / RENDERSIZE.y;
    p *= scale;
    p += 0.5;
	float e, f; 
	vec3 g, h, j, k, q; 
	if (flip) { f = gl_FragCoord.x; } 
  	else f = gl_FragCoord.y;
  	float freq2 = 25.;
  	e = sin( floor(freq2) * f + fbm( floor(freq) * p) + fbm( floor(freq2) * p) + fbm( floor(freq3) * p));
	g = vec3(e);
	h = mix( g,vec3(1.0, 0.0, 0.0), 1.0); // 1.0
	j = mix( g,vec3(0.0, 1.0, 0.0), 0.61 + 0.06 * colormod); // 0.67
	k = mix( g,vec3(0.0, 0.0, 1.0), 0.58 + 0.23 * colormod); // 0.81
	float offset2 = 0.59;
	q = vec3( reflect( reflect( offset + h ,offset1 - j ), offset2 + k ));
	if (invert) { gl_FragColor = vec4( 1.0 - vec3(q), 1.0); }
	else gl_FragColor = vec4( q, 1.0); 
}