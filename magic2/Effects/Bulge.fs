/*{
	"DESCRIPTION": "Bulge FX",
	"CREDIT": "by IMIMOT (ported from https://github.com/BradLarson/GPUImage)",
	"CATEGORIES": [
		"Distortion Effect"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "radius",
			"TYPE": "float",
			"DEFAULT": 0.25,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "scale",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
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

void main()
{
    vec2 textureCoordinate = vv_FragNormCoord;
     
	float aspectRatio = RENDERSIZE.y/RENDERSIZE.x;
     
    vec2 textureCoordinateToUse = vec2(textureCoordinate.x, (textureCoordinate.y * aspectRatio + 0.5 - 0.5 * aspectRatio));
    float dist = distance(center, textureCoordinateToUse);
    textureCoordinateToUse = textureCoordinate;
    
    if (dist < radius)
    {
        textureCoordinateToUse -= center;
        float percent = 1.0 - ((radius - dist) / radius) * scale;
        percent = percent * percent;
        
        textureCoordinateToUse = textureCoordinateToUse * percent;
        textureCoordinateToUse += center;
    }
    
     
     gl_FragColor = IMG_NORM_PIXEL(inputImage, textureCoordinateToUse);
  
}
