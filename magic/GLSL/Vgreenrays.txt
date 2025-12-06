#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;
vec2 position;

float wave(float freq, float offset)
{
	return ((sin(position.x * 6.28 * freq + offset)) + 1.0) * 0.15;	
}

void main( void ) {

	position = (gl_FragCoord.xy / resolution.xy);
	
	float depth = wave(64.0, time) + wave(4.0, -time * 1.0) + wave(32.0, time * 4.0);
	
	depth = pow(depth, 3.);
	depth = clamp(depth, 0.0, 1.0);
	depth = sqrt(depth) + 0.189;
	
	vec3 final = vec3(depth) * pow(position.y, 1.3);
	final = pow(final, vec3(1.4, 0.8 + (pow(1.0 - position.y, 1.0)), 1.1));

	gl_FragColor = vec4(final, 1.0);
}