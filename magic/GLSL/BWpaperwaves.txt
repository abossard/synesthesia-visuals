#ifdef GL_ES
precision mediump float;
#endif

// this is a test of the floating point precision (dashxdr)
// how many intact vertical bars do you see, starting from the left...

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	float x = (gl_FragCoord.x / resolution.x) * 20.0;
	float y = (gl_FragCoord.y / resolution.y) * 5.0;

	float xp = sin(x + time);

	float color = fract(xp + fract(y));
//	if(fract(x) > .9) color = 0.0;

	gl_FragColor = vec4( color, color, color, 1.0 );

}