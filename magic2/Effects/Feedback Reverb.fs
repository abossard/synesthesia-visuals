/*{
  "DESCRIPTION": "trails",
  "CREDIT": "INKA",
  "CATEGORIES": [
    "Feedback"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "feedback",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 1.0
    },
    {
      "NAME": "highPass",
      "TYPE": "float",
      "DEFAULT": 0.4,
      "MAX": 0.5
    },
    {
      "NAME": "lowPass",
      "TYPE": "float",
      "DEFAULT": 0.7,
      "MIN": 0.5
    },
    {
      "NAME": "zoom",
      "TYPE": "float",

      "DEFAULT": 0.07
    },
    
    {
      "NAME": "yPos",
      "TYPE": "float",
      "MIN": -0.5,
      "MAX": 0.5,
      "DEFAULT": 0.09
    },
    {
      "NAME": "darken",
      "TYPE": "float",
      "DEFAULT": 0.1
    }
  ],
  "PASSES" : [
    {
      "TARGET" : "BufferA",
      "PERSISTENT" : true
    },
    {

    }
  ]
}*/



float gray(vec4 n) {
	return (n.r + n.g + n.b)/3.0;
}


mat2 rotmat( float deg ) {
	float theta = radians(deg);
	float s = sin(theta);
	float c = cos(theta);

	return mat2(c, -s, s, c);
}

void main()
{
	vec2 uv =  gl_FragCoord.xy / RENDERSIZE.xy;
	vec4 color;

	if (PASSINDEX == 0)	{
		vec4 original = IMG_THIS_PIXEL(inputImage);
 		vec2 warp = (uv - 0.5) * (1.0 + zoom * 0.05);
 		
		warp += 0.5;
		warp.y += 0.005 * (yPos);
		
 		color = IMG_NORM_PIXEL(BufferA, warp); 
 		
		color.rgb -= 0.001 + darken * 0.05;
		float luma = gray(original);
		
		if(luma > highPass && luma < lowPass) {
			color = original;
		}

		gl_FragColor = mix(original, color, feedback);
	}
	else if (PASSINDEX == 1)	{	
		color = IMG_THIS_PIXEL(BufferA);
			
		gl_FragColor = color;
	}
}
