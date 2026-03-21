/*{
	"CREDIT": "by kawaiiidesu",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"generator"
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
				1.0
			]
		},
	 {
      "NAME": "freq",
      "TYPE": "float",
      "MAX": 1,
      "MIN": 0,
      "DEFAULT": 0.5
    }
	]
}*/

void main() {

	float t;
	t=ceil(cos(TIME * (freq * 50.)));
	gl_FragColor = t == 1.0 ? colorInput*t: IMG_THIS_PIXEL(inputImage);
}