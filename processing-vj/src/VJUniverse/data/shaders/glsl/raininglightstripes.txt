#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	float px = gl_FragCoord.x/500.;
	float py = gl_FragCoord.y/500.;
	float x = sin(px*100.)+sin(time)/2.;
	float y = sin(py*10.+time*2.5);
	float v = 0.5 / x * y;
	gl_FragColor = vec4(v+sin(time),v,v+cos(time),1.0);
}