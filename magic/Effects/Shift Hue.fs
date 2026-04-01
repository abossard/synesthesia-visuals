/*{
	"CREDIT": "by isak.burstrom",
	"DESCRIPTION": "Shift hue while preserving luma.",
	"CATEGORIES": [
		"INKA",
		"Color Adjustment"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
	    {
	      "NAME" : "amount",
	      "TYPE" : "float",
	      "LABEL" : "Hue Shift",
	      "DEFAULT": 0.5
	    }
	]
}*/

// Converted from http://stackoverflow.com/questions/9234724/how-to-change-hue-of-a-texture-with-glsl/9234854#9234854

#define PI 3.141592654
vec3 hueShift(vec3 color, float dhue) {
	float s = sin(dhue);
	float c = cos(dhue);
	return (color * c) + (color * s) * mat3(
		vec3(0.167444, 0.329213, -0.496657),
		vec3(-0.327948, 0.035669, 0.292279),
		vec3(1.250268, -1.047561, -0.202707)
	) + dot(vec3(0.299, 0.587, 0.114), color) * (1.0 - c);
}
void main() {
	vec4 color = IMG_THIS_PIXEL(inputImage);

	gl_FragColor = vec4(hueShift(color.rgb, amount * PI * 2.), color.a);
}