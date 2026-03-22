
/*{
	"DESCRIPTION": "Repeating the image with correct junctions.",
	"CREDIT": "Paul Racanière",
	"ISFVSN": "2",
	"CATEGORIES": ["Tile Effect"],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
		    "NAME": "repeats",
		    "TYPE": "float",
		    "MIN": 1,
		    "MAX": 20,
		    "DEFAULT": 5
		}
	]
}*/

float hat(float x) {
    return 1.0 - 2.0 * abs(x - 0.5);
}

vec2 hat(vec2 x) {
    return 1.0 - 2.0 * abs(x - 0.5);
}

void main()	{
	vec2 loc = isf_FragNormCoord;
	
	loc.xy = hat(mod(loc.xy * repeats / 2.0, 1.0));
	
	gl_FragColor = IMG_NORM_PIXEL(inputImage, loc);
}
