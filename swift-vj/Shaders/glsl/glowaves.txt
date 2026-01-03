#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );
	
	float hr = position.y - (sin(position.x*30.0 - time* 4.0)*0.2 + 0.5);
	float hg = position.y - (sin(position.x*50.0 - time* 5.0)*0.1 + 0.5);
	float hb = position.y - (sin(position.x*20.0 - time* 4.0)*0.2 + 0.5);

	float fr = pow(1.0-hr*hg, 1000.0);
	float fg = pow(1.0-hg*hb, 100.0);
	float fb = pow(1.0-hb*hr, 100.0) * 2.0;
	
	gl_FragColor = vec4( fr, fg, fb, 1.0 );

}