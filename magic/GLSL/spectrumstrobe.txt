#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 xyZeroToOne = gl_FragCoord.xy / resolution;
	float zeroToOneWave = sin( time ) * 0.5 + 0.5;
	
	float red = sin( zeroToOneWave * xyZeroToOne.x + time * 1.0 );
	float green = cos( xyZeroToOne.y * 2.0 + time * 50.0 );
	float blue = sin( xyZeroToOne.x * 35.0 + time * 50.0 );
	
	gl_FragColor = vec4( red, green, blue * sin( time * 5.0 ), 1.0 );
}