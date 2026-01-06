#ifdef GL_ES
precision mediump float;
#endif
#define pi 3.141592653589793238462643383279

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	// How fast it animates
	float tscale = 2.5;
	
	float magnitude = 1.0-abs(gl_FragCoord.y - resolution.y/2.0)/resolution.y;
	magnitude *= abs(sin((time+gl_FragCoord.x/10.0)));
	// normalize position
	vec2 position = gl_FragCoord.xy / resolution.xy;
	
	gl_FragColor = vec4(magnitude, gl_FragCoord.x/ resolution.x, gl_FragCoord.y/ resolution.y,1.0);
}