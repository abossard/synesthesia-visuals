#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );
	position += vec2(5.0, 5.0);
	float T = time + 1.0;
	
	float x = gl_FragCoord.x - gl_FragCoord.y;
	float y = gl_FragCoord.x - gl_FragCoord.y;
	float b = 0.0, g = 0.0, r = 0.0;
	r = sin(x / resolution.x + time / 1.0) / 5.0 + 0.3 + sin(gl_FragCoord.x * gl_FragCoord.y * 2.0) / 20.0;
	g = sin(x / resolution.x + time / 2.0) / 5.0 + 0.3 + sin(gl_FragCoord.x * gl_FragCoord.y * 2.0) / 20.0;
	b = sin(x / resolution.x + time / 3.0) / 5.0 + 0.3 + sin(gl_FragCoord.x * gl_FragCoord.y * 2.0) / 20.0;
	
	gl_FragColor = vec4(r, g, b, 1.0);
}