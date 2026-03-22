/*{
	"CREDIT": "by isadoratelesdecastro",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"Gradient"
	],
	"INPUTS": [
		{
			"NAME": "colorA",
			"TYPE": "color",
			"DEFAULT": [
				1.0,
				0.0,
				0.0,
				1.0
			]
		},
		{
			"NAME": "colorB",
			"TYPE": "color",
			"DEFAULT": [
				0.0,
				0.0,
				1.0,
				1.0
			]
		},
		{
			"NAME": "offset",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 10.0
		}
	]
}*/

/*
float f(x)
{
	float result = sin(4*x)/x;
	return result;
}
*/

float random (vec2 st) 
{
    return fract(sin(dot(st.xy, vec2(12.9898,78.233)))*43758.5453123);
}

void main() 
{
	vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
	vec3 pct = vec3(uv.y);
	
	//pct.r = sin(uv.y*colorA.r);
	//pct.g = sin(uv.x*colorB.g);
	gl_FragColor = mix(colorA, colorB, pct.b*offset);
}













