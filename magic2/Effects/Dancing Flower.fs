/*
{
  "CATEGORIES" : [
    "Feedback"
  ],
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "amount",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "movement",
      "TYPE" : "float",
      "DEFAULT": 0.3
    }
  ],
  "PASSES" : [
    {
      "TARGET" : "BufferA",
      "PERSISTENT" : true
    },
    {

    }
  ],
  "ISFVSN" : "2"
}
*/

// Hash without Sine
// https://www.shadertoy.com/view/4djSRW
#define NOISEVEC vec3(443.8975,397.2973, 491.1871)

//  1 out, 2 in...
float noise(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * NOISEVEC);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


float gray(vec4 n) {
	return (n.r + n.g + n.b)/3.0;
}


void main() {
	if (PASSINDEX == 0)	{

        float spin = 0.01 + movement * 0.5;
        float random = 0.8 + movement;
        float saturation = 0.35;
        float brightness = 0.59 - movement;
        float huemod = 0.0 + movement * 0.8;
	    vec2 res = RENDERSIZE.xy;
	    vec2 uv = gl_FragCoord.xy / res;
	    uv = -1.0 + 2.0 * uv;
	    uv = uv *0.5 + 0.5;
	    
	    vec4 rand = vec4(noise(uv * 0.5 + TIME));
	    
	    vec4 fb = IMG_NORM_PIXEL(BufferA, uv);
		vec2 pos = uv + vec2(fb.y - fb.x, fb.x - fb.z) * ((spin * 20.) / res);
	    vec4 colOut = IMG_NORM_PIXEL(BufferA, pos);
	    
	    colOut.rgb = rgb2hsv(colOut.rgb);
	    
	    colOut.r += huemod * 0.01;
	    colOut.g += saturation * 0.01;
	    colOut.b += (-.005 * random) + (-0.001 + 0.002 * brightness);
	  
	    colOut.rgb = hsv2rgb(colOut.rgb);
	    colOut.rgb += rand.rgb * 0.01 * random;
	    
	    
	    vec4 inputPixelColor = IMG_NORM_PIXEL(inputImage,uv);
	    //mix(, colOut,  sqrt(amount))
		//float val = inputPixelColor.a * (inputPixelColor.r + inputPixelColor.g + inputPixelColor.b) / 3.0;
	//	inputPixelColor = (val >= tresh) ? inputPixelColor : colOut;
	//	inputPixelColor.a = 1.0;
		
		
		
	    gl_FragColor = gray(inputPixelColor) > amount ? inputPixelColor : colOut;
	    
	}
	else if (PASSINDEX == 1) {
		gl_FragColor = IMG_THIS_PIXEL(BufferA);
	}
}
