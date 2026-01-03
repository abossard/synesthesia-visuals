#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

#define numLegs 5.0	//non integers look terrible
#define wibblewobble 5.5

void main(void) {

	vec2 p = -1.0+2.0*gl_FragCoord.xy/resolution.xy;
	float dist		= length(p);
	
	float w = -sin(sqrt(dot(p,p))+time); 	//part 2 -- bend
	float x = cos(numLegs*atan(p.y,p.x)+50.0*w);	//part 1 -- legs and fade
	
	//vec3 col = vec3(0.1,0.2,0.82)*15.0;
	vec3 brightColor = vec3(0.1,0.1,0.1)*15.0;
	float brightColorFade = min( max( 1.0 - dist * 1.0 , 0.0 ), 1.0 );
	

	//gl_FragColor = vec4(brightColor*x, 1.0);
	gl_FragColor = vec4(brightColor*x*brightColorFade, 1.0);
	
}