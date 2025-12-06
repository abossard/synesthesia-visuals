#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	//vec2 p = -1.0 + 2.0 * gl_FragCoord.xy / resolution.xy;
	vec2 p = -1.0 + 2.0 * gl_FragCoord.xy / resolution.xy;
	float circleRadius=sqrt(p.x*p.x+p.y*p.y)-time/5.0;
	float angle=atan(p.x/p.y)+time;//mod(time,3.14159);
	float modulo=mod(circleRadius,0.2);
	if (modulo>0.0&&modulo<0.1)
		gl_FragColor = vec4(1.0,mod(angle,1.0),0.0,1.0);
	//gl_FragColor = vec4(p.x,p.y,0.0,1.0);
}