
/*{
	"DESCRIPTION": "",
	"CREDIT": "",
	"ISFVSN": "2",
	"CATEGORIES": [
		"Color"
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
				0.0,
				0.0,
				0.0,
				0.0
			]
		},
		{
			"NAME": "alpha",
			"TYPE": "float",
			"DEFAULT": 1.0
		}
	]
	
}*/

void main()	{
	gl_FragColor = vec4(colorInput.rgb, alpha);
}
