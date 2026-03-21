/*{
  "CREDIT": "by zoidberg",
  "CATEGORIES": [
    "Color Adjustment"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "vibrancy",
      "TYPE": "float",
      "MIN": 0.0,
      "MAX": 1.0,
      "DEFAULT": 0
    }
  ]
}*/

void main() {
	vec4 color = IMG_THIS_PIXEL(inputImage);

    float average = (color.r + color.g + color.b) / 3.;
    float mx = max(color.r, max(color.g, color.b));
    float amount = (mx - average) * vibrancy * 3. * 5.;
    color = color - (mx - color) * amount;


	gl_FragColor = color;
}
