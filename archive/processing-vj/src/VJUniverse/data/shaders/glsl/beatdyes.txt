#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	gl_FragColor = vec4(mod(time + cos(gl_FragCoord.x / 10.0) * sin(gl_FragCoord.y / 40.0), 1.0), 
			    mod(time + cos(gl_FragCoord.x / 20.0) * sin(gl_FragCoord.y / 50.0), 1.0), 
			    mod(time + cos(gl_FragCoord.x / 30.0) * sin(gl_FragCoord.y / 60.0), 1.0), 
			    1.0);
}