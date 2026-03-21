
/*{
	"DESCRIPTION": "",
	"ISFVSN": "2",
    "CREDIT": "by mojovideotech",
    "CATEGORIES" : [
        "generator",
        "gradient",
        "rainbow"
    ],
	"INPUTS": [
    {
   		"NAME": 	"vertical",
     	"TYPE": 	"bool",
     	"DEFAULT": 	false
   	}
  ]
}
*/

////////////////////////////////////////////////////////////
// RainbowGradientTurbo   by mojovideotech
//
// based on 
// glslsandbox//e#57479.14
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////


vec3 turbo(float x) {
    float r = 0.1357 + x * (4.5974 - x * (42.3277 - x * (130.5887 - x * (150.5666 - x * 58.1375))));
    float g = 0.0914 + x * (2.1856 + x * (4.8052 - x * (14.0195 - x * (4.2109 + x * 2.7747))));
    float b = 0.1067 + x * (12.5925 - x * (60.1097 - x * (109.0745 - x * (88.5066 - x * 26.8183))));
    return vec3(r,g,b);
}


void main( void ) 
{
	vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy; 
	float c = uv.x;
	if (vertical) c = uv.y;
	gl_FragColor = vec4(turbo(c), 1.0);
}

