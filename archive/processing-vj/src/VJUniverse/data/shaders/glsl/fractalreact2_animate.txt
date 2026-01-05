#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );

	float x = 2.0*(position.x - 0.5);
	float y = 2.0*(position.y - 0.5);
	float a = mouse.x;
	float b = mouse.y;
	for (int count = 0; count < 100; count++) {
		float xx = x*x - y*y + a;
		y = 2.0 * x * y + b;
		x = xx;
		if (x*x + y*y > 50.0) {
			break;
		}
	}
	
	float color = x*x + y*y;
	
	gl_FragColor = vec4( color, x, y, 1.0 );

}