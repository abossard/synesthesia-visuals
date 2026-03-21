/*{
  "DESCRIPTION": "levels, vignette, 5 colors gradient map",
  "CREDIT": "INKA",
  "CATEGORIES": [
    "INKA",
    "Color Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "gamma",
      "TYPE": "float",
      "DEFAULT": 0.12
    },
    {
      "NAME": "exposure",
      "TYPE": "float",
      "DEFAULT": 0
    },
    {
      "NAME": "blackLevel",
      "TYPE": "float",
      "DEFAULT": 0.11,
      "MAX": 0.5
    },
    {
      "NAME": "whiteLevel",
      "TYPE": "float",
      "DEFAULT": 0,
      "MAX": 0.5
    },
    {
      "NAME": "contrast",
      "TYPE": "float",
      "DEFAULT": 0.5
    },
    {
      "NAME": "vignette",
      "TYPE": "float",
      "DEFAULT": 0.5
    },
    {
      "NAME": "vibrance",
      "TYPE": "float",
      "MIN": -3,
      "MAX": 4,
      "DEFAULT": 0.8
    }
  ]
}*/


vec3 rgb2hsv(vec3 c);
vec3 hsv2rgb(vec3 c);

vec3 rgb2hsv(vec3 c)	{
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = c.g < c.b ? vec4(c.bg, K.wz) : vec4(c.gb, K.xy);
	vec4 q = c.r < p.x ? vec4(p.xyw, c.r) : vec4(c.r, p.yzx);
	
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)	{
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main(void) {
	vec4 color = IMG_PIXEL(inputImage, gl_FragCoord.xy);
	
	// VIGNETTE
	vec4 vignettecolor;
	if(vignette > 0.0) {
	    vec2 coord = (isf_FragNormCoord.xy - 0.5) * (RENDERSIZE.x / RENDERSIZE.y) * 1.;
	    float rf = sqrt(dot(coord, coord)) * vignette;
	    float rf2_1 = rf * rf + 1.0;
	    float e = 1.0 / (rf2_1 * rf2_1);
	    color *= vec4(e);
	}
	
	// VIBRANCE
	vec3 tmpColorB = rgb2hsv(color.rgb);
	float maxDelta = sqrt(tmpColorB.y) - tmpColorB.y;
	
	tmpColorB.y = (maxDelta * vibrance) + tmpColorB.y;
	color.rgb = hsv2rgb(tmpColorB.rgb);

	
	//LEVELS
	vec4 inputRange = min(max(color - vec4(gamma), vec4(0.0)) / (vec4(1.0 - exposure) - vec4(gamma)), vec4(1.0));
	inputRange = pow(inputRange, vec4(1.0 / (1.5 - contrast)));
	
	color = mix(vec4(blackLevel), vec4(1.0 - whiteLevel), inputRange);
	
	gl_FragColor = color;
}
