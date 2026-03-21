/*{
  "CREDIT": "by carter rosenberg",
  "CATEGORIES": [
    "Distortion Effect",
    "Geometry Adjustment"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "level",
      "TYPE": "float",
      "MIN": 0.8,
      "MAX": 1.2,
      "DEFAULT": 1
    },
    {
      "NAME": "center",
      "TYPE": "point2D",
      "DEFAULT": [
        0.5,
        0.5
      ]
    }
  ]
}*/

void main() {
	vec2		loc;
	vec2		modifiedCenter;
	
	loc = isf_FragNormCoord;
	modifiedCenter = center;
	loc.x = (loc.x - modifiedCenter.x)*(1.0/level) + modifiedCenter.x;
	loc.y = (loc.y - modifiedCenter.y)*(1.0/level) + modifiedCenter.y;
	if ((loc.x < 0.0)||(loc.y < 0.0)||(loc.x > 1.0)||(loc.y > 1.0))	{
		gl_FragColor = vec4(0.0);
	}
	else	{
		gl_FragColor = IMG_NORM_PIXEL(inputImage,loc);
	}
}
