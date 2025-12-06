#ifdef GL_ES
precision lowp float;
#endif

uniform float time;
uniform vec2 resolution;
vec2 position;

float wave(float freq, float offset)
{
	return ((sin(position.x * 5.28 * freq + offset)) + 1.0) * 0.15;	
}

void main( void ) {

	position = (gl_FragCoord.xy / resolution.xy);
	
	float depth = wave(64.0, time) + wave(4.0, -time * 1.0) + wave(32.0, time * 4.0);
	
	depth = pow(depth, 2.);
	depth = clamp(depth, 0.11, 4.0);
	depth = sqrt(depth) + 0.589;
	
	vec3 final = vec3(depth) * pow(position.y, 0.1);
	final = pow(final, vec3(0.8, 0.9 + (pow(1.0 - position.y, 1.0)), 2.1));

	gl_FragColor = vec4(final, 1.0);
}