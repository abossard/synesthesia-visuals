
/*{
  "CREDIT": "by VIDVOX",
  "CATEGORIES": [
    "Stylize"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "sides",
      "TYPE": "float",
      "MIN": 1,
      "MAX": 32,
      "DEFAULT": 6
    },
    {
      "NAME": "angle",
      "TYPE": "float",
      "MIN": -1,
      "MAX": 1,
      "DEFAULT": 0
    },
    {
      "NAME": "slidex",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 0.5
    },
    {
      "NAME": "slidey",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 0
    }
  ]
}*/


const float tau = 6.28318530718;




void main() {
  // normalize to the center
  	//vec2 center = vec2(0.5);
	
    float minSize = min(RENDERSIZE.x, RENDERSIZE.y);
    vec2 ratio = vec2(RENDERSIZE.x / minSize, RENDERSIZE.y / minSize);
    
    vec2 center = 0.5 * ratio;
        // normalize to the center
    vec2 loc = isf_FragNormCoord * ratio;
    float r = distance(center, loc);
    float a = atan(abs(loc.y-center.y)/abs(loc.x-center.x));
    
    // kaleidoscope
    a = mod(a, tau/sides);
    a = abs(a - tau/sides/2.);
    
    loc.x = r * cos(a);
    loc.y = r * sin(a);
    
    loc = (center + loc);
    
    loc.x = mod(loc.x + slidex, 1.0);
    loc.y = mod(loc.y + slidey, 1.0);

	// sample the image
	gl_FragColor = IMG_NORM_PIXEL(inputImage, loc);;
}