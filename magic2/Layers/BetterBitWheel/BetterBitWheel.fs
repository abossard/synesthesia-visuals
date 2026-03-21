/*{
	"CREDIT": "by mojovideotech",
	"DESCRIPTION": "",
	"CATEGORIES": [
		    "generator",
    		"2d",
    		"rotation",
    		"circular"
	],
	"INPUTS": [
	{
		"NAME" : 		"scale",
		"TYPE" : 		"float",
		"DEFAULT" : 	1.5,
		"MIN" : 		0.5,
		"MAX" : 		3.0
	},
	{
		"NAME" : 		"rate",
		"TYPE" : 		"float",
		"DEFAULT" : 	5.0,
		"MIN" : 		-10.0,
		"MAX" : 		10.0
	},
	{
     	"NAME" :		"seed1",
     	"TYPE" : 		"float",
     	"DEFAULT" :		13,
     	"MIN" : 		8,
     	"MAX" :			233
	},
    {
      	"NAME" :		"seed2",
      	"TYPE" :		"float",
      	"DEFAULT" :		5987,
      	"MIN" : 		1597,
      	"MAX" :			8999	
	},
    {
     	"NAME" :		"seed3",
      	"TYPE" :		"float",
     	"DEFAULT" :		75025,
     	"MIN" :			9859,
     	"MAX" :			28657
    },
	{
		"NAME" : 		"loops",
		"TYPE" : 		"float",
		"DEFAULT" :	 	3.0,
		"MIN" : 		1.0,
		"MAX" : 		60.0
	},
	{
		"NAME" : 		"thickness",
		"TYPE" : 		"float",
		"DEFAULT" : 	0.6,
		"MIN" : 		0.5,
		"MAX" : 		0.99
	},
	{
		"NAME" : 		"density",
		"TYPE" : 		"float",
		"DEFAULT" : 	0.5,
		"MIN" : 		0.001,
		"MAX" : 		0.999
	},
	{
		"NAME" : 		"fade",
		"TYPE" : 		"float",
		"DEFAULT" : 	1.5,
		"MIN" : 		0.0,
		"MAX" : 		3.0
	}
	]
}*/


///////////////////////////////////////////
// BetterBitWheel  by mojovideotech
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
///////////////////////////////////////////

#define 	pi	3.141592653589793	// pi


float hash( vec2 h ) {
    return fract( sin( dot( h.xy, vec2( seed1, seed2 ) ) ) * seed3 );
}

float T = TIME * rate;
float L = floor(loops);
float N = 1.0 - thickness;

vec4 draw( vec2 p ) {
	float r = length( p ) * RENDERSIZE.y * 0.05;
	r /= scale;
	float layer = floor( r );
	
	if ( 2.0 < layer ) {
		float theta = ( atan( p.y, p.x ) + pi ) / 2.0 / pi;
		float V = 0.05 * ( hash( vec2( layer, 3.155 ) ) - 0.5 );
		float F = 1.0 + floor( layer * 4.0 * pow( hash( vec2( layer, 2.456 ) ), 2.0 ) );
		
		float phase = fract( ( theta + T * V ) * L ) * F;
		float phase0 = floor( phase );
		float phase1 = mod( phase0 + 1.0, F );
		float phasec = fract( phase );
		
		float state0 = hash( vec2( layer, phase0 ) ) < density ? 0.0 : 1.0;
		float state1 = hash( vec2( layer, phase1 ) ) < density ? 0.0 : 1.0;
		float state = mix( state0, state1, smoothstep( 0.0, 0.5 / RENDERSIZE.y * L * F / length( p ), phasec ) );
		
		vec3 col = vec3( state );
		
		float layerc = mod( r, 1.0 );
		col *= smoothstep( 0.0, 0.0 + N, layerc );
		col *= smoothstep( 0.6, 0.6 - N, layerc );
		
		col *= exp( -fade * length( p ) );
		
		return vec4( col, 1.0 );
	} else {
		return vec4( 0.0, 0.0, 0.0, 1.0 );
	}
}

void main() {
	vec2 pos = ( gl_FragCoord.xy * 2.0 - RENDERSIZE.xy ) / RENDERSIZE.y;
    gl_FragColor = draw( pos );
}

