
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
				1.0,
				1.0,
				1.0,
				0.0
			]
		},
		{
			"NAME": "phase",
			"TYPE": "float",
			"DEFAULT": 0.5
		}
	]
	
}*/

void main() {
    vec4 base = IMG_THIS_PIXEL(inputImage);
    // Blend based on phase amount
    vec3 blendedColor = mix(base.rgb, colorInput.rgb, phase);
    
    // Output the result with the alpha of the base layer
    gl_FragColor = vec4(blendedColor, base.a);
}