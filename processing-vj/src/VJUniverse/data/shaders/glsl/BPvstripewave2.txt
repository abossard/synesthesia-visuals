#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy);
	float y = position.x;
	float x = position.y;
	
	if (y < sin(x + time)*0.5 + 0.7 && y > sin(x + time)*0.5 + 0.4) {
		float c = (x * y) - time;
		gl_FragColor = vec4(sin(c), 0.25, 0.5, 1);
	} else {
		float c = time;
		gl_FragColor = vec4(0, 0, 0, 1);
	}
}