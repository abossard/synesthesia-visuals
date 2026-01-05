#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
float PI = 3.14159265358979323846264;
void main( void ) {

	vec2 position = ( (gl_FragCoord.xy / resolution.xy) -mouse.xy );

	if (position.xy == vec2(0.0,0.0)) {
		gl_FragColor=vec4(0.0,0.0,0.0,1.0);
	} else {
		float angle = atan(position.x,position.y)+time;
		gl_FragColor = vec4( vec3((cos(angle-(3.0*PI/2.0))+1.0)/2.0,(sin(angle)+1.0)/2.0,(sin(angle+(3.0*PI/2.0))+1.0)/2.0), 1.0 ) * pow(sin(angle+length(position)*200.),.1);
	}

}