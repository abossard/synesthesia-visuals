#ifdef GL_ES
precision mediump float;
#endif

// This should be the starting point of every effect - dist

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	vec2 position = (( gl_FragCoord.xy / resolution.xy ) - 0.5) / vec2(resolution.y/resolution.x, 1.0);
	vec3 color = vec3(0.);
	float angle = atan(position.y,position.x);
	float d = length(position);
	
	color.r = sin(angle*3.)*0.5 * sin(sin(angle)*4.+time*3.)*0.5 + 0.5;
	color.r *= sin(d*128. - time*2.)*0.5 + 0.5;
	
	gl_FragColor = vec4(color, 1.0);
}