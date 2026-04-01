/*{
	"CREDIT": "by isak.burstrom",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"Color Effect"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		}, {
			"NAME": "contrast",
			"TYPE": "float",
			"DEFAULT": 0.5
		}
	]
}*/

void main() {
	vec4 color = IMG_THIS_PIXEL(inputImage);
	color.rgb = ((vec3(2.0) * (color.rgb - vec3(0.5))) * vec3(contrast * 2.) / vec3(2.0)) + vec3(0.5);
	gl_FragColor = color;
}
