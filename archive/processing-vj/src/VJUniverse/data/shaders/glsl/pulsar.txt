#ifdef GL_ES
precision mediump float;
#endif

// A sun looking thing
// by zach@cs.utexas

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float rand( vec2 co ) {
   return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void main( void ) {
	
	
	float PI = 4.0*atan(1.0);
	
	float pos = rand(gl_FragCoord.xy);
	
	float distx = length(abs(gl_FragCoord.x - resolution.x/2.));
	float disty = length(abs(gl_FragCoord.y - resolution.y/2.0));
	float radius = sqrt(distx*distx + disty*disty);
	
	vec4 color = vec4(0.0, 0.0, 0.0, 1.0);
	
	if (radius < 1000.0) {
		color = vec4(48.0/radius * (1.0 + sin(time)), 24.0/radius * (1.0 + cos(time)), 6.0/radius * (1.0 + tan(time)), 1.0);
	}
	
	gl_FragColor = color;
}