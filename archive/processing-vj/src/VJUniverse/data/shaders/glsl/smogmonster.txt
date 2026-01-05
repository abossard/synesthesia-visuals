/** 
 *  @title 	Cloud Demo 
 *  @version 	v0.3
 *  @author 	Mark Sleith
 *  @website 	www.cngames.co.uk/portfolio
 *  @date 	15/08/2012
 *
 *  @note	Noise and fBm from iq's latest live coding video, "a simple eye ball".
 *
 *  @todo	Add varying cloud density, cloud illumination.
 */


#ifdef GL_ES
	precision mediump float;
#endif

#define CLOUD_COVER		0.75
#define CLOUD_SHARPNESS		0.095

uniform float time;
uniform vec2  mouse;
uniform vec2  resolution;

float hash( float n )
{
	return fract(sin(n)*43758.5453);
}

float noise( in vec2 x )
{
	vec2 p = floor(x);
	vec2 f = fract(x);
    	f = f*f*(3.0-2.0*f);
    	float n = p.x + p.y*57.0;
    	float res = mix(mix( hash(n+  0.0), hash(n+  1.0),f.x), mix( hash(n+ 57.0), hash(n+ 58.0),f.x),f.y);
    	return res;
}

float fbm( vec2 p )
{
    	float f = 0.0;
    	f += 0.50000*noise( p ); p = p*2.02;
    	f += 0.25000*noise( p ); p = p*2.03;
    	f += 0.12500*noise( p ); p = p*2.01;
    	f += 0.06250*noise( p ); p = p*2.04;
    	f += 0.03125*noise( p );
    	return f/0.984375;
}

// Entry point
void main( void ) {
	// Set up domain
	vec2 q = ( gl_FragCoord.xy / resolution.xy );
	vec2 p = -1.0 + 2.0 * q;
	
	// Fix aspect ratio
	p.x *= resolution.x / resolution.y;

	// Create noise using fBm
	float f = fbm(  9. * vec2(p.y + sin(time), p.x - cos(p.y)) );

	vec3 myCol = vec3( fbm(2. * p), fbm(p/2.), fbm(p.yx) );

        myCol *= 4.;
	float cover = CLOUD_COVER;
	float sharpness = CLOUD_SHARPNESS;
	
	float c = f - (1.0 - cover);
	if ( c < 0.0 )
		c = 0.0;
	
	f = 1.0 - (pow(sharpness, c));

	
	
	gl_FragColor = vec4( f * myCol.r, f * myCol.g, f * myCol.b, f);
} 
