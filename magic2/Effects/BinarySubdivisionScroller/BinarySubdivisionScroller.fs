/*{
  "CREDIT": "by mojovideotech",
  "DESCRIPTION": "",
  "CATEGORIES": [
    "Geometry Adjustment"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "reverse",
      "TYPE": "bool",
      "DEFAULT": 0
    },
    {
      "NAME": "rate",
      "TYPE": "float",
      "DEFAULT": 0.125,
      "MIN": 0.01,
      "MAX": 2.5
    }
  ]
}*/

////////////////////////////////////////////////////////////
// BinarySubdivisionScroller  by mojovideotech
//
// based on :
// shadertoy.com/\ll2SW3
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////

void main() {
	float T = TIME * rate;
	vec2 uv = isf_FragNormCoord.xy;
	if (reverse) T = -T;
    uv /= exp2(fract(T));
    gl_FragColor = IMG_NORM_PIXEL(inputImage, mod(fract(exp2(ceil(-log2(uv.y * 0.5))) * uv / 2.0), 1.0));
}