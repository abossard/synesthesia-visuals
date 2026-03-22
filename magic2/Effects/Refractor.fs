/*{
  "DESCRIPTION": "Takes two inputs and fakes refraction",
  "CREDIT": "by you",
  "CATEGORIES": [
    "Distortion Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "XAMOUNT",
      "TYPE": "float",
      "DEFAULT": 0.1,
      "MIN": -1,
      "MAX": 1
    },
    {
      "NAME": "YAMOUNT",
      "TYPE": "float",
      "DEFAULT": 0.1,
      "MIN": -1,
      "MAX": 1
    }
  ]
}*/

// Takes two inputs and fakes refraction by XAMOUNT and YAMOUNT
// Based on: https://magicmusicvisuals.com/forums/viewtopic.php?f=3&t=529&p=2675&hilit=refract#p2675

void main(void) {
    
	vec2 uv = gl_FragCoord.xy / RENDERSIZE;
    
    vec4 r = IMG_NORM_PIXEL(inputImage,uv);
    
    uv = uv + vec2(r.x * XAMOUNT*2.,r.y * YAMOUNT*2.);
    gl_FragColor = IMG_NORM_PIXEL(inputImage,uv);
}