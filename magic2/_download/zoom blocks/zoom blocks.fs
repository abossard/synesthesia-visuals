/*{
	"DESCRIPTION": "",
	"CREDIT": "spleen666@gmail.com",
	"ISFVSN": "2",
	"CATEGORIES": [ 
		"blocks",
		"feedback",
		"zoom"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "zoom",
			"TYPE": "float",
			"DEFAULT": 0.98,
			"MIN": 0.95,
			"MAX": 1.05
		},
		{
			"NAME": "feedbackFade",
			"TYPE": "float",
			"DEFAULT": 0.8,
			"MIN": 0.8,
			"MAX": 1.0
		},
		{
			"NAME": "sampleSpeed",
			"TYPE": "float",
			"DEFAULT": 5.0,
			"MIN": 0.0,
			"MAX": 10.0
		},
		{
			"NAME": "blockSize",
			"TYPE": "float",
			"DEFAULT": 0.05,
			"MIN": 0.01,
			"MAX": 0.2
		}
	],
	"PASSES": [
		{
			"TARGET": "oldBuffer",
			"PERSISTENT": true
		}
	]
}*/

#define R RENDERSIZE 
#define t TIME

#define luma( rgba ) ( dot(rgba, vec3(0.299, 0.587, 0.114, 0.0)) )

const vec4 seed = vec4(12.9898,78.233, 45.666,  43758.5453123);

float random (vec2 vec) {
    return abs(fract(sin(dot(vec.xy, seed.xy)) * seed.w));
}

float rand1(float x) {
    return random(vec2(x, 2.123*x));
}

vec2 rand2(float x) {
    return vec2(rand1(x), rand1(1.17856*x));
}

void main() {
    vec2 pos = isf_FragNormCoord.xy;
    vec2 center = vec2(0.5, 0.5);
    
    vec2 oldpos = zoom * (pos - center) + center;
    
    float t = sampleSpeed * TIME - fract(sampleSpeed * TIME);
    
    vec2 A = rand2(t);
    vec2 B = rand2(t+32.562);
    
    float xmin = min(A.x, B.x);
    float xmax = max(A.x, B.x);
    float ymin = min(A.y, B.y);
    float ymax = max(A.y, B.y);
    
    float alpha = 0.7;
    alpha *= step(xmin, pos.x) * (1.0 - step(xmax, pos.x));
    alpha *= step(ymin, pos.y) * (1.0 - step(ymax, pos.y));
    
    vec2 offset = blockSize * (rand2(t) - 0.5);
    vec4 color = IMG_NORM_PIXEL(inputImage, pos + offset);
    vec4 oldPixel = IMG_NORM_PIXEL(oldBuffer, oldpos);
    
    color = vec4(alpha * color.xyz, 1.0);
    gl_FragColor = max(color, feedbackFade * (color * 1e-2 + oldPixel));
}
