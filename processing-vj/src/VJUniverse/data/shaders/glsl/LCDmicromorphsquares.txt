#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

//~~~~~~~~ by @greweb

#define DIVISOR_SIZE 4.0
#define PATTERN_INTENSITY 0.5

float pixelPatternMultiplicator (vec2 p) {
	vec2 part = fract(p*resolution/DIVISOR_SIZE);
	float m = 1.0-PATTERN_INTENSITY*smoothstep(0.6, 1.0, distance(part, vec2(0.0, 1.0)));
	return m;
}

//~~~~~~~~~

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) + mouse / 4.0;

	float color = 0.0;
	color += sin( position.x * cos( time / 15.0 ) * 80.0 ) + cos( position.y * cos( time / 15.0 ) * 10.0 );
	color += sin( position.y * sin( time / 10.0 ) * 40.0 ) + cos( position.x * sin( time / 25.0 ) * 40.0 );
	color += sin( position.x * sin( time / 5.0 ) * 10.0 ) + sin( position.y * sin( time / 35.0 ) * 80.0 );
	color *= sin( time / 10.0 ) * 0.5;

	gl_FragColor = vec4( vec3( position.x+color, position.y+color * 0.5, sin( color + time / 3.0 ) * 0.75 ) * pixelPatternMultiplicator(gl_FragCoord.xy / resolution.xy), 1.0 );
}