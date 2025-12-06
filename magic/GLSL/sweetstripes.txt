#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = gl_FragCoord.xy + mouse.xy*100.0;
	
	float r = position.x*2.0;
	float g = sin(position.x/20.0 + time * 1.5);
	float b = cos(position.y/30.0)*sin(time)*6.0;
		

	gl_FragColor = vec4( vec3( r, g, b), 1.0 );
}