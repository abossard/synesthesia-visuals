/*{
	"CREDIT": "by INKA, based on color controls",
	"DESCRIPTION": "just a simple brightness filter",
	"CATEGORIES": [
		"Color Adjustment"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "brightness",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1.0,
			"DEFAULT": 0.1
		},
		{
			"NAME": "multiply",
			"TYPE": "bool",
			"DEFAULT": true
		}
	]
}*/


void main() {
	vec4		color = IMG_THIS_PIXEL(inputImage);
	
	color = mix(color + vec4(brightness, brightness, brightness, 0.0), 
            color * vec4(brightness + 1.0, brightness + 1.0, brightness + 1.0, 1.0), 
            float(multiply));

	gl_FragColor = color;
}


