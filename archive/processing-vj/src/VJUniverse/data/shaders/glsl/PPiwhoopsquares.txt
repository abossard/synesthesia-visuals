#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	vec2 p = -1.0 + 2.0 * gl_FragCoord.xy / resolution.xy;
	float r = sin(gl_FragCoord.x) * dot(p,p);
	float b = mod(sin(p.x+gl_FragCoord.x/100.0)*cos(p.y+gl_FragCoord.y/100.0)+time,0.5);
	float g = 1.0+sin(gl_FragCoord.x/2.0)+cos(gl_FragCoord.y/2.0);
	gl_FragColor = vec4(r,b,g,1.0);
}