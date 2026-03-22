/*{
  "CREDIT": "by isak.burstrom",
  "CATEGORIES": [
    "Color Effect", "INKA"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "colorShift",
      "TYPE": "float",
      "DEFAULT": 0.55
    },
    {
      "NAME": "colorAdjust",
      "TYPE": "float",
      "DEFAULT": 1.0,
      "MIN": 0.25,
      "MAX": 2.0
    },
    {
      "NAME": "blacks",
      "TYPE": "float",
      "DEFAULT": 0.7
    }
  ]
}*/

const vec4 lumcoeff = vec4(0.299, 0.587, 0.114, 0.0);

vec3 palette( float t ) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.263,0.416,0.557);

    return 0.15 + a + b*cos( 6.28318*(c*t+d) );
}

void main() {
	vec4 srcPixel = IMG_THIS_PIXEL(inputImage);
	float luma = dot(srcPixel, lumcoeff);
	vec3 paletteCol = palette(colorShift + luma * colorAdjust);
	vec4 colorOut = vec4(paletteCol.rgb, srcPixel.a);
	;
	gl_FragColor =mix(vec4(srcPixel.rgb, 0.0), colorOut, min(1., blacks == 0.0 ? 1.0 : (luma / blacks)));
}
