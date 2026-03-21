
/*{
	"DESCRIPTION": "",
	"CREDIT": "",
	"ISFVSN": "2",
	"CATEGORIES": [
		"Color Effect"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "amount",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "color",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "saturate",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.0,
			"MAX": 1.0
		}
	],
	"PASSES": [
		{
			"TARGET":"bufferVariableNameA",
			"WIDTH": "$WIDTH/16.0",
			"HEIGHT": "$HEIGHT/16.0"
		},
		{
			"DESCRIPTION": "this empty pass is rendered at the same rez as whatever you are running the ISF filter at- the previous step rendered an image at one-sixteenth the res, so this step ensures that the output is full-size"
		}
	]
	
}*/

vec3 hsv2rgb(vec3 c)	{
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void main()	{
	vec3 lumcoeff = vec3(0.299, 0.7, 0.1);
	//	both of these are the same
	
	
	vec4 originalColor = IMG_THIS_PIXEL(inputImage);
	vec4 inputColor = originalColor;
	inputColor.rgb = abs(1.0 - inputColor.rgb);
	
    vec3 darkColor = hsv2rgb(vec3(color, saturate * 0.5, 0.9));
    vec3 brightColor = hsv2rgb(vec3(mod(1.0, color + 0.45), saturate, 0.2));

    vec3 shiftColor = mix(darkColor, brightColor, dot(inputColor.rgb, lumcoeff));
    
    vec3 outColor = abs((inputColor.rgb) - shiftColor);
    
	gl_FragColor = vec4(mix(originalColor.rgb, outColor, amount), 1.0);
}
