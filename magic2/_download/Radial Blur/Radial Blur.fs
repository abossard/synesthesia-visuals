/*{
	"DESCRIPTION": "Your shader description",
	"CREDIT": "by you",
	"CATEGORIES": [
		"Sharpen And Blur"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "x",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1.0,
			"DEFAULT": 0.5
		},
		{
			"NAME": "y",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1.0,
			"DEFAULT": 0.5
		},
		{
			"NAME": "amount",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1.0,
			"DEFAULT": 0.97
		},
		{
			"NAME": "strength",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 1.0,
			"DEFAULT": 0.5
		},
		{
			"NAME": "jitter",
			"TYPE": "float",
			"MIN": 0.0,
			"MAX": 20.0,
			"DEFAULT": 1.0
		}
      	]
}*/

vec3 iResolution = vec3(RENDERSIZE, 1.);
float iGlobalTime = TIME;

/*
	Full Scene Radial Blur
	----------------------

	Radial blur - as a postprocessing effect - is one of the first things I considered doing 
	when the multipass system came out. I've always loved this effect. Reminds me of the early 
	demos from Aardbei et al. 

	Anyway, Shadertoy user, Passion, did a really cool radial blur on a field of spheres that
	inspired me to do my own. Radial blurs are pretty straight forward, but it was still
    helpful to have Passion's version as a guide. 

    As for the radial blur process, there's not much to it. Start off at the pixel position, 
    then radiate outwards gathering up pixels with decreased weighting. The result is a
	blurring of the image in a radial fashion, strangely enough. :)

	Inspired by:

	Blue Dream - Passion
	https://www.shadertoy.com/view/MdG3RD

	Radial Blur - IQ
	https://www.shadertoy.com/view/4sfGRn

	Rays of Blinding Light - mu6k
	https://www.shadertoy.com/view/lsf3Dn

*/

// PORTED / ADAPTED from "Full Scene Radial Blur" by Shane: https://www.shadertoy.com/view/XsKGRW


// The radial blur section. Shadertoy user, Passion, did a good enough job, so I've used a
// slightly trimmed down version of that. By the way, there are accumulative weighting 
// methods that do a slightly better job, but this method is good enough for this example.

// Ported/ Adapted from "Full Scene Radial Blur" by Shane: https://www.shadertoy.com/view/XsKGRW

// Radial blur samples. More is always better, but there's frame rate to consider.
// const float SAMPLES = 24.; 

// 2x1 hash. Used to jitter the samples.

// RV Comments: Just took out and simplified a bunch of params, as well as adjusting some ranges for more sweet spot.

float hash( vec2 p ){ return fract(sin(dot(p, vec2(41, 289)))*45758.5453); }

void mainImage( out vec4 fragColor, in vec2 fragCoord ){
    
    // Screen coordinates.
    vec2 uv = fragCoord.xy / iResolution.xy;
    
    float weight = .1;

    // Radial blur factors.
    //
    // Falloff, as we radiate outwards.
    // float decay = 0.97; 
    
    // Controls the sample density, which in turn, controls the sample spread.
    // float density = 0.5; 
    
    // Sample weight. Decays as we radiate outwards.
    // float weight = 0.1; 
    
    // Light offset. Kind of fake. See above.
    //vec3 l = lOff();
    
    vec3 l = vec3(x*2.-1.,y*2.-1.,0.);
    
    // Offset texture position (uv - .5), offset again by the fake light movement.
    // It's used to set the blur direction (a direction vector of sorts), and is used 
    // later to center the spotlight.
    //
    // The range is centered on zero, which allows the accumulation to spread out in
    // all directions. Ie; It's radial.
    
    vec2 tuv =  uv - .5 - l.xy*.5;
    
    // Dividing the direction vector above by the sample number and a density factor
    // which controls how far the blur spreads out. Higher density means a greater 
    // blur radius.
    
    vec2 dTuv = tuv*1./16./2.  * strength;
    
    // Grabbing a portion of the initial texture sample. Higher numbers will make the
    // scene a little clearer, but I'm going for a bit of abstraction.
    
    vec4 col = IMG_NORM_PIXEL(inputImage, uv.xy)*(1.-amount);
    
    // Jittering, to get rid of banding. Vitally important when accumulating discontinuous 
    // samples, especially when only a few layers are being used.
    
    uv += dTuv*(hash(uv.xy + fract(iGlobalTime))*jitter - jitter/2.);
    
    // The radial blur loop. Take a texture sample, move a little in the direction of
    // the radial direction vector (dTuv) then take another, slightly less weighted,
    // sample, add it to the total, then repeat the process until done.
    
    for(float i=0.; i < 16.; i++){
        uv -= dTuv;
        col += IMG_NORM_PIXEL(inputImage, uv) * weight * amount;
        weight = weight * 0.9;
        
    }
    
    // Multiplying the final color with a spotlight centered on the focal point of the radial
    // blur. It's a nice finishing touch... that Passion came up with. If it's a good idea,
    // it didn't come from me. :)
    
    //col *= (1. - dot(tuv, tuv)*vignette);
    
    // Smoothstepping the final color, just to bring it out a bit, then applying some 
    // loose gamma correction.
    
    fragColor = sqrt(smoothstep(0., 1., col));
    
  
}



void main(void) {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}