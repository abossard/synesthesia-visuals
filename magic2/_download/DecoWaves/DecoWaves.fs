/*{
	"CREDIT": "by mojovideotech",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"generator"
	],
	"INPUTS": [
		{
			"NAME": "colorInput",
			"TYPE": "color",
			"DEFAULT": [
				0.0,
				0.0,
				1.0,
				1.0
			]
		},
		{
			"NAME": "rate",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": -2.0,
			"MAX": 2.0
		},
		{
			"NAME": "rows",
			"TYPE": "float",
			"DEFAULT": 6.0,
			"MIN": 1.0,
			"MAX": 10.0
		},
		{
			"NAME": "wave",
			"TYPE": "float",
			"DEFAULT": 3.0,
			"MIN": 2.0,
			"MAX": 12.0
		}
	]
}*/

////////////////////////////////////////////////////////////
// DecoWaves  by mojovideotech
//
// based on :
// glslsandbox.com/\e#45253.2
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////


void main() {
	float T = TIME * rate;
	vec2 U = floor(rows) * gl_FragCoord.xy/RENDERSIZE.y; 
	U.x -= T;
	vec2 V = floor(U);
	U.y = dot(cos((2.0*(T+V.x) + 7.0 + wave - V.y) * max(0.0, 0.5 - length(U = fract(U) - 0.5)) - vec2(33.0, 0.0)), U);
	gl_FragColor = clamp(vec4(smoothstep(-1.5, 0.5, sqrt(U)).y) + colorInput, 0.0, 1.0);
}