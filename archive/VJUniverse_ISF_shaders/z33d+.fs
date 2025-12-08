/*{
	"DESCRIPTION": "based https://www.shadertoy.com/view/XlXcWj",
	"CATEGORIES": ["fractal", "generator"],
	"INPUTS": [
		{
			"NAME": "mX",
			"TYPE": "float",
			"DEFAULT": 0.67,
			"MIN": 0.0,
			"MAX": 2.0
		},
		{
			"NAME": "mY",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.0,
			"MAX": 2.0
		},
		{
			"NAME": "rate",
			"TYPE": "float",
			"DEFAULT": 1.75,
			"MIN": -3.0,
			"MAX": 3.0
		},
		{
			"NAME": "e",
			"TYPE": "float",
			"DEFAULT": 0.025,
			"MIN": 0.0005,
			"MAX": 0.1
		}
	]
}*/

////////////////////////////////////////////////////////////
// z33d+  by mojovideotech
//
// mod of :
// interactiveshaderformat.com/\2109
// based on :
// shadertoy.com/\XlXcWj
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////

void main()
{  
	float k = 0.0, T = TIME*rate*0.1;
	vec2 R = RENDERSIZE.xy;
  	vec2 M = vec2(mX,mY)*R.xy;
  	for (float i = 0.0; i < 12.0; i++) {
    	vec3 p = vec3((2.0 * gl_FragCoord.xy - R.xy) / R.yy, k - 1.);
    	float a = T;
    	p.zy *= mat2(cos(a), -sin(a), sin(a), cos(a));
	 	a /= 2.0;
    	p.yx *= mat2(cos(a), -sin(a), sin(a), cos(a));
    	a /= 2.0;
    	p.zx *= mat2(cos(a), -sin(a), sin(a), cos(a));
    	vec3 z = p;
    	float c = 2.0;
    	for (float i = 0.; i < 9.0; i++) {
      		float r = length(z);
        	if (r > 6.0) { 
        		k += log(r) * r / c / 3.0;
				break;
        	}
      		float a = acos(z.z / r) * (6.0 + 12.0 * M.x / R.x);
      		float b = atan(z.y, z.x) * (6.0 + 12.0 * M.y / R.y);
      		c = pow(r, 7.0) * 5.0 * c / r + 1.0;
      		z = pow(r, 7.0) * vec3(sin(a) * cos(b), -sin(a) * sin(b), -cos(a)) + p;
    	}
    	gl_FragColor = vec4(1.0 - i / 16.0 - k + p / 4.0, 1.0);
      	if (log(length(z)) * length(z) / c < e) {
       		break;
    	}
  	}
}

