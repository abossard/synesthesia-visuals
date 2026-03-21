/*{
  "CREDIT": "by VIDVOX",
  "CATEGORIES": [
    "Tile Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "angle",
      "LABEL": "Angle",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 0
    },
    {
      "NAME": "level",
      "TYPE": "float",
      "MIN": 0.2,
      "MAX": 1.5,
      "DEFAULT": 1
    },
    {
      "NAME": "shift",
      "LABEL": "Shift",
      "TYPE": "point2D",
      "DEFAULT": [
        0,
        0.5
      ]
    }
  ]
}*/


varying vec2 translated_coord;


void main() {
	vec2 loc = translated_coord;
	vec2 modifiedCenter = shift / RENDERSIZE;
	
	
	loc.x = (loc.x - modifiedCenter.x - 0.5) * (1.0/level) + modifiedCenter.x + 0.5;
	loc.y = (loc.y - modifiedCenter.y - 0.5) * (1.0/level) + modifiedCenter.y + 0.5;
	
	loc = mod(loc + modifiedCenter, 1.0);
	
	//	mirror the image so it's repeated 4 times at different reflections
	loc = 2.0 * abs(loc - 0.5);
	
	gl_FragColor = IMG_NORM_PIXEL(inputImage, loc);
}