/*{
	"CREDIT": "by spleen666",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"generative",
		"red",
		"black",
		"circle",
		"moon",
		"sin",
		"cos"
	],
	"INPUTS": [
        {
          "NAME": "inputImage",
          "TYPE": "image"
        },
		{
			"NAME": "colorInput",
			"TYPE": "color",
			"DEFAULT": [
				1.0,
				0.0,
				0.0,
				1.0
			]
		},
		{
			"NAME": "floatInputY",
			"TYPE": "float",
			"DEFAULT": 2.5,
			"MIN": 0.0,
			"MAX": 10.0
		},
		{
			"NAME": "floatRadius",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.25,
			"MAX": 1.0
		},
		{
			"NAME": "floatCircleSpread",
			"TYPE": "float",
			"DEFAULT": 50.0,
			"MIN": 0.0,
			"MAX": 100.0
		}
	
	]
}*/


#define R RENDERSIZE
#define time TIME

void main() {
	
	// [-1, +1] along shortest side
	vec2 uv = ( 2.* gl_FragCoord.xy - R ) / min(R.x,R.y);
	
	vec4 tex = IMG_NORM_PIXEL(inputImage, uv);
	
	vec3 col = colorInput.rgb *  cos( uv.y*floatInputY + time + clamp( 1.0 / ( floatCircleSpread*abs( length(uv.xy) - floatRadius ) ), 0.0, 1.0) );
	
	gl_FragColor = vec4(col, 1.0); 
}
