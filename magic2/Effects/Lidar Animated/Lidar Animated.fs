/*{
  "DESCRIPTION": "LIDAR",
  "CREDIT": "by you",
  "CATEGORIES": [
    "Glitch",
    "Stylize"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "DEPTH",
      "TYPE": "float",
      "DEFAULT": 60,
      "MAX": 100,
      "MIN": 5
    },
    {
      "NAME": "EXTRUSION",
      "TYPE": "float",
      "DEFAULT": -0.4,
      "MAX": 1,
      "MIN": -1
    },
    {
      "NAME": "SAMPLERADIUS",
      "TYPE": "float",
      "DEFAULT": 12,
      "MAX": 20,
      "MIN": 0
    },
    {
      "NAME": "SAMPLES",
      "TYPE": "float",
      "DEFAULT": 64,
      "MAX": 128,
      "MIN": 16
    },
    {
      "NAME": "CHUNKINESS",
      "TYPE": "float",
      "DEFAULT": -8,
      "MAX": 20,
      "MIN": -20
    },
    {
      "NAME": "WARPFACTORA",
      "TYPE": "float",
      "DEFAULT": 0.74,
      "MAX": 5,
      "MIN": 0.025
    },
    {
      "NAME": "WARPFACTORB",
      "TYPE": "float",
      "DEFAULT": 1.0,
      "MAX": 5,
      "MIN": 0
    },
    {
      "NAME": "OVERLOAD",
      "TYPE": "float",
      "DEFAULT": 0,
      "MAX": 1,
      "MIN": 0
    },
    {
      "NAME": "TIMEOFFSET",
      "TYPE": "float",
      "DEFAULT": 0.0,
      "MAX": 1,
      "MIN": 0
    },
    {
      "NAME": "TIMEDILATION",
      "TYPE": "float",
      "DEFAULT": 1,
      "MAX": 1,
      "MIN": -1
    },
    {
      "NAME": "SPEED",
      "TYPE": "float",
      "DEFAULT": 40.0,
      "MAX": 50.0,
      "MIN": 0.0
    },
    {
      "NAME": "GAMMA",
      "TYPE": "float",
      "DEFAULT": 2.2,
      "MAX": 10,
      "MIN": 0
    }
  ]
}*/

// Based off "Interstellar" by TekF: https://www.shadertoy.com/view/Xdl3D2

// SAMPLERADIUS is the distance to sample data fromt he centre of the input
// WARPFACTORA smears the dots into streaks
// WARPFACTORB offsets the RGB channels
// DEPTH scales the output in the Z-AXIS
// EXTRUSION is the amount to displace points based on brightness of input
// OVERLOAD is a multiplier for the DEPTH
// TIMEOFFSET allows you to pick a point in time. Useful for still images when TIMEDILATION is 0.
// TIMEDILATION allows for speed of zoom in apps that donot support SPEED control
// GAMMA adjusts contrast

const float tau = 6.28318530717958647692;

// Gamma correction
// #define GAMMA (2.2)

vec3 ToLinear( in vec3 col )
{
	// simulate a monitor, converting colour values into light values
	return pow( col, vec3(GAMMA) );
}

vec3 ToGamma( in vec3 col )
{
	// convert back into colour values, so the correct light will come out of the monitor
	return pow( col, vec3(1.0/GAMMA) );
}

float GetLuma(vec2 uvPos) {
    vec3 col = IMG_NORM_PIXEL(inputImage, uvPos).rgb;
    return dot(col, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	vec3 ray;
	ray.xy = 10. * (gl_FragCoord.xy-RENDERSIZE.xy*0.5)/RENDERSIZE.xy;
	ray.z = 1.0-OVERLOAD;

	float offset = TIME*.01 * SPEED;	
	
	vec3 col = vec3(0);
	
	vec3 stp = ray/max(abs(ray.x),abs(ray.y));
	
	vec3 pos = 1.0*stp+.5;
	for ( int i=0; i < 64; i++ )
	{
		
        vec2 uvPos = 0.5 + (pos.xy / RENDERSIZE.x * SAMPLERADIUS);
        
        float luma = GetLuma(uvPos);
        if (uvPos.x < 0.0 || uvPos.y < 0.0 || uvPos.x > 1.0 || uvPos.y > 1.0 ) {
            pos += stp; 
            break;
        }
		
		float z = luma*EXTRUSION;
		z = fract(z-offset*TIMEDILATION+TIMEOFFSET);
		float d = DEPTH*z-pos.z;
		float w = pow(max(0.0,1.0+CHUNKINESS*length(fract(pos.xy)-.5)),2.0);
		vec3 c = max(vec3(0),vec3(1.0-abs(d+WARPFACTORB*.5)/WARPFACTORA,1.0-abs(d)/WARPFACTORA,1.0-abs(d-WARPFACTORB*.5)/WARPFACTORA));
        col += 1.5 * (1.0 - z) * c * w * (luma > 0.15 ? 1.0 : luma / 0.15);
		pos += stp;
	}
	
	gl_FragColor = vec4(ToGamma(col),1.0);
}