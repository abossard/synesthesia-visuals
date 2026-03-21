
/*{
  "CREDIT": "by zoidberg",
  "CATEGORIES": [
    "Color Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
	{
		"NAME": "invert",
		"TYPE": "float",
		"DEFAULT": 0.5,
		"MIN": 0.0,
		"MAX": 1.0
	}
  ]
}*/
void main()	{
	vec4 inputPixelColor;
	inputPixelColor = IMG_THIS_PIXEL(inputImage);
	
	inputPixelColor.rgb = abs((invert) - inputPixelColor.rgb);
	
	gl_FragColor = inputPixelColor;
}
