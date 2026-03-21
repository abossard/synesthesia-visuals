
/*{
	"CREDIT": "by INKA",
	"CATEGORIES": [
		"Distortion Effect",
		"INKA"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "distortion",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 5.0,
			"DEFAULT": 2.0
		},
		{
			"NAME": "frequency",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1,
			"DEFAULT": 0.1
		},
		{
			"NAME": "period",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1.0,
			"DEFAULT": 0.3
		}
	]
}*/

#define PI 3.141592654

vec2 pb(in vec2 uv, in float per){
    uv.y += (period * PI * 2.) / per;
    vec2 result = (cos(uv.y * per)) * normalize(vec2(1., cos((uv.y) * per)));
    return result;
}


void main(void) {
    
	vec2 uv = (gl_FragCoord.xy / RENDERSIZE.xy);
	
    vec2 hpert = pb(uv, frequency * 100.0);
    uv += hpert * distortion * .108;
    
    vec4 col = IMG_NORM_PIXEL(inputImage, uv);
	gl_FragColor = col;
	
}