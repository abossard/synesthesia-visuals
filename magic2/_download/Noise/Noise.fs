/*{
  "CREDIT": "by INKA",
  "DESCRIPTION": "Hash noise",
  "CATEGORIES": [
    "Stylize",
    "INKA"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "noiseLevel",
      "TYPE": "float",
      "DEFAULT": 0.14,
      "MIN": 0,
      "MAX": 1
    }
  ]
}*/

// Hash without Sine
// https://www.shadertoy.com/view/4djSRW
#define NOISEVEC vec3(443.8975,397.2973, 491.1871)

//  1 out, 2 in...
float noise(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * NOISEVEC);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}


void main( void ) 
{
	vec2 uv = (gl_FragCoord.xy + TIME);
	uv = vec2(atan(uv.x, uv.y), length(uv));
	vec4 noise1 = vec4(noise(uv)) * noiseLevel;
	vec4 noise2 = vec4(noise(uv + 10.)) * noiseLevel;
	gl_FragColor = IMG_NORM_PIXEL(inputImage, isf_FragNormCoord.xy) + noise1 - noise2;
}