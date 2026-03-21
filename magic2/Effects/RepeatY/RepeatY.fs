
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
		},
		{
		    "NAME": "crop",
		    "TYPE": "float",
		    "MIN": 0,
		    "MAX": 1,
		    "DEFAULT": 0.5
		}
	]
}*/


void main()	{
	vec2 loc = isf_FragNormCoord;
	float cropped = exp(1.0 - crop * 3.0);
	loc.y = mod(loc.y * repeats / 2.0, 1.0);
	loc.y = (loc.y -0.5) * cropped + 0.5;
	
	loc.x = (loc.x - 0.5)*(repeats / 2.0) + 0.5;
	loc.x = (loc.x -0.5) * cropped + 0.5;

    bool isOutside = ((loc.x < 0.0) || (loc.y < 0.0) || (loc.x > 1.0) || (loc.y > 1.0));
    gl_FragColor = isOutside ? vec4(0.0) : IMG_NORM_PIXEL(inputImage, loc);
}
