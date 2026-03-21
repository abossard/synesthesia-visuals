/*{
  "CREDIT": "by isak.burstrom",
  "CATEGORIES": [
    "XXX",
    "INKA"
  ],
  "DESCRIPTION": "Based on: https://www.shadertoy.com/view/ldtGD8",
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "pos",
      "TYPE": "float"
    },
    {
      "NAME": "mixup",
      "TYPE": "float",
      "DEFAULT": 1.0
    },
    {
      "NAME": "mod1",
      "TYPE": "float",
      "DEFAULT": 0.45
    },
    {
      "NAME": "mod2",
      "TYPE": "float"
    }
  ],
  "ISFVSN": "2"
}*/

#define PI 3.141592654

// Codegolfed 134chars version by FabriceNeyret2 & coyote
void main() {
	vec2 I = gl_FragCoord.xy;
	//vec2 R = RENDERSIZE.xy;
	vec4 o = vec4(0.);
    vec2 R = RENDERSIZE.xy; 
    I = (I + I - R) / R.y * (0.1 + mod1); 
	
	//I = isf_FragNormCoord;
	//modifiedCenter = center / RENDERSIZE;
    
   	//I =  ( (I + I) / 10.) * 0.5;

	
	//loc = isf_FragNormCoord;
	//modifiedCenter = center / RENDERSIZE;
	
	//vec2 locR = (loc - modifiedCenter
    //I =  vec2(0.5 - length(I), PI * 0.5 + atan(I.x, I.y));
    I = vec2(0.5 / length(I), atan(I.y, I.x));

    //o -= 4./I.x; // dark
    o -= .03 * I.x; // light ****
    I.x += (pos * 2. * PI);
    I = 0.5 + sin(I);
	
    I = fract(I);

	vec2 coord = mix(isf_FragNormCoord, I, mixup);
	
	vec4 color = IMG_NORM_PIXEL(inputImage, coord);
	
	color += o * (mixup);
	
	gl_FragColor = color;
}