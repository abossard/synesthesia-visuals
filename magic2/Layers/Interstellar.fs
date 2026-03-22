
/*{
	"DESCRIPTION": "",
	"CREDIT": "",
	"ISFVSN": "2",
	"CATEGORIES": [
		"Space"
	],
	"INPUTS": [
		{
			"NAME": "stellar",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "timePosition",
			"TYPE": "float",
			"DEFAULT": 0.3,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "amount",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
		}
	]
	
}*/


// Interstellar
// Hazel Quantock
// This code is licensed under the CC0 license http://creativecommons.org/publicdomain/zero/1.0/

const float tau = 6.28318530717958647692;

// Gamma correction
#define GAMMA (2.2)

vec4 noiseGen(vec2 x){
    vec4 v = vec4(x.x, x.y, 0.0, 0.0);
    // ensure reasonable range
    v = fract(v) + fract(v*1e4) + fract(v*1e-4);
    // seed
    v += vec4(0.12345, 0.6789, 0.314159, 0.271828);
    // more iterations => more random
    v = fract(v*dot(v, v)*123.456);
    v = fract(v*dot(v, v)*123.456);
    return v;
}

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

vec4 Noise( in ivec2 x ) {
    vec2 thePos = (vec2(x) + 0.5) / 256.0;
	return noiseGen(thePos);
}


vec4 Rand( in int x )
{
	vec2 uv;
	uv.x = (float(x)+0.5)/256.0;
	uv.y = (floor(uv.x)+0.5)/256.0;
	return noiseGen( uv );
}

vec4 noise(vec4 v) {
    // ensure reasonable range
    v = fract(v) + fract(v*1e4) + fract(v*1e-4);
    // seed
    v += vec4(0.12345, 0.6789, 0.314159, 0.271828);
    // more iterations => more random
    v = fract(v*dot(v, v)*123.456);
    v = fract(v*dot(v, v)*123.456);
    return v;
}


void main()	{
	vec3 ray;
	ray.xy = 2.0 * (gl_FragCoord.xy - RENDERSIZE.xy*.5)/RENDERSIZE.x;
	ray.z = 1.0;

	float offset = stellar*.5;	
	float speed2 = (stellar * 2.)*2.0;
	float speed = speed2+.1;
	offset += sin(offset)*.96;
	offset *= 2.0;
	
	
	vec3 col = vec3(0);
	
	vec3 stp = ray/max(abs(ray.x),abs(ray.y));
	
	vec3 pos = 2.0*stp+.5;
	int times = int(amount * 20.);
	for ( int i=0; i < 20; i++ )
	{
	   if(i>times) {
	       continue;
	   }
		float z = Noise(ivec2(pos.xy)).x;
		z = fract(z-TIME * timePosition);
		float d = 50.0*z-pos.z;
		float w = pow(max(0.0,1.0-8.0*length(fract(pos.xy)-.5)),2.0);
		vec3 c = max(vec3(0),vec3(1.0-abs(d+speed2*.5)/speed,1.0-abs(d)/speed,1.0-abs(d-speed2*.5)/speed));
		col += 1.5*(1.0-z)*c*w;
		pos += stp;
	}
	
	gl_FragColor = vec4(ToGamma(col),1.0);
}
