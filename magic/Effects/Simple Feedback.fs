
/*{
	"DESCRIPTION": "",
	"CREDIT": "",
	"ISFVSN": "2",
	"CATEGORIES": [
		"Feedback"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "amount",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "zoom",
			"TYPE": "float",
			"DEFAULT": 0.4,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "darken",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.0,
			"MAX": 1.0
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

float gray(vec4 sourcePixel) {
    return length(sourcePixel.rgb * vec3(0.2126,0.7152,0.0722));

}

void main()	{
    if(PASSINDEX == 0) {
    	vec4 originalColor = IMG_THIS_PIXEL(inputImage);;
    
        vec2 uv = isf_FragNormCoord;
        
        float zoom = 1.0 - zoom;
        float passThrough = amount;
            
        vec4 color;
        vec2 warp = 0.5 + ((uv - 0.5) * (0.98 + zoom * 0.05));
        
        if ((warp.x < 0.0) || (warp.y < 0.0) || (warp.x > 1.0) || (warp.y > 1.0)) {
            color = vec4(0.0);
        } else {
            color = IMG_NORM_PIXEL(BufferA, warp);
        }
        
        color -= 0.005 * darken * 2.0;
        
        if(gray(originalColor) > passThrough) {
            color = originalColor;
        }
        
    	gl_FragColor = color;
    } else if (PASSINDEX == 1) {
        gl_FragColor = IMG_THIS_PIXEL(BufferA);
    }
}
