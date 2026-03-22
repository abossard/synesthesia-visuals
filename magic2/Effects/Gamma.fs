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
      "NAME": "gamma",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 0.5
    }
  ]
}*/



void main() {
	vec4 color = IMG_THIS_PIXEL(inputImage);
	color.rgb = pow(color.rgb, vec3(1.0/(1.0 - gamma)));
	gl_FragColor = color;
}
