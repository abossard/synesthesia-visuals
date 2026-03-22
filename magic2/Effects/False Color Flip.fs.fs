/*{
  "CREDIT": "by rhythmic visions",
  "CATEGORIES": [
    "Color Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "brightColor",
      "TYPE": "color",
      "DEFAULT": [
        0.5,
        0.0,
        0.0,
        1
      ]
    },
    {
      "NAME": "darkColor",
      "TYPE": "color",
      "DEFAULT": [
        1.0,
        0.5,
        0.0,
        1
      ]
    },
    {
        "NAME": "amount",
        "TYPE": "float",
        "DEFAULT": 0.5
    }
  ]
}*/

const vec4		lumcoeff = vec4(0.299, 0.587, 0.114, 0.0);

void main() {
	vec4		srcPixel = IMG_THIS_PIXEL(inputImage);
	float		luminance = dot(srcPixel,lumcoeff);
	
    float blendBottom = min(1.0, amount * 2.0); // 0 1.0 1.0
    float blendTop = max(0.0, (amount - 0.5) * 2.0); // 0.0 0.0 1.0
    vec4 blendColor = mix(darkColor, brightColor, luminance);

	gl_FragColor = vec4(abs((srcPixel.rgb * (1.0 - blendTop)) - blendColor.rgb * blendBottom), 1.0);
}
