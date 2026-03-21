/*{
	"DESCRIPTION": "Pixel with brightness levels below the threshold do not update.",
	"CREDIT": "by VIDVOX",
	"CATEGORIES": [
		"Glitch"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "amount",
			"LABEL": "Threshold",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1.0,
			"DEFAULT": 0.99
		}
	],
	"PERSISTENT_BUFFERS": [
		"BufferA"
	],
	"PASSES": [
		{
			"TARGET":"BufferA"
		},
		{
		
		}
	]
	
}*/

void main()
{
	vec4		freshPixel = IMG_PIXEL(inputImage,gl_FragCoord.xy);
	vec4		stalePixel = IMG_PIXEL(BufferA,gl_FragCoord.xy);

	gl_FragColor = mix(freshPixel,stalePixel, amount * 0.99);
}
