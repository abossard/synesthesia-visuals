// SaturdayShader Week 26 : Soft Patterns
// by Joseph Fiola (http://www.joefiola.com)
// 2016-02-13

// Based on Interferance, Color Waves by @gabrieldunne
// https://twitter.com/gabrieldunne/status/671398225593561090
// http://glslsandbox.com/e#29006.1



/*{
  "CREDIT": "",
  "DESCRIPTION": "",
  "CATEGORIES": [
    "Generator"
  ],
  "INPUTS": [
    {
      "NAME": "zoom",
      "TYPE": "float",
      "DEFAULT": 4,
      "MIN": 0,
      "MAX": 50
    },
    {
      "NAME": "iterations",
      "TYPE": "float",
      "DEFAULT": 10,
      "MIN": 0,
      "MAX": 10
    },
    {
      "NAME": "contrast",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": -20,
      "MAX": 20
    },
    {
      "NAME": "offset",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": 0,
      "MAX": 1
    },
    {
      "NAME": "pattern",
      "TYPE": "float",
      "DEFAULT": 1,
      "MIN": 0,
      "MAX": 1
    },
    {
      "NAME": "rotate",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": -1,
      "MAX": 1
    },
    {
      "NAME": "color1",
      "TYPE": "color",
      "DEFAULT": [
        1,
        0.8,
        0,
        1
      ]
    },
    {
      "NAME": "color2",
      "TYPE": "color",
      "DEFAULT": [0,0,0,1]
    }
  ]
}*/



#define PI 3.14159
#define TWO_PI (PI*2.0)


vec2 rot(vec2 uv,float a){
	return vec2(uv.x*cos(a) -uv.y*sin(a),uv.y*cos(a)+uv.x*sin(a));
}


void main() 
{
	vec2 center = (gl_FragCoord.xy);
	vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
	uv -= vec2(0.5);
	uv.x *= RENDERSIZE.x/RENDERSIZE.y;
	uv *= zoom;
	uv=rot(uv,rotate * PI);

	float col = contrast;

	for(float i = 0.; i < 10.0; i++) 
	{
	  	float a = i * 4. * (TWO_PI * pattern / 10.);
		col += cos(TWO_PI*(uv.y * cos(a) + uv.x * sin(a) + offset)) +cos(TWO_PI*(uv.y * cos(a) + uv.x * sin(-a) + offset));
		
		if (i >= iterations) break;
		
	}
	
	gl_FragColor = col > 0.5 ? color1 : color2;
}