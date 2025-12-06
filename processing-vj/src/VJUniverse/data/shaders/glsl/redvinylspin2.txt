#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float orbitDistance = 0.025;
float waveLength = 200.;

void main( void ) {
	vec2 p1 = (vec2(sin(time), cos(time))*orbitDistance)+0.5;
	vec2 p2 = (vec2(sin(time+3.142), cos(time+3.142))*orbitDistance)+0.5;

	float d1 = 1.-length(gl_FragCoord.xy/resolution -p1);
	float d2 = 1.-length(gl_FragCoord.xy/resolution -p2);

	float wave1 = sin(d1*waveLength+(time*5.))*0.5 + 0.5 * (((d1 - 0.5) * 2.) + 0.5);
	float wave2 = sin(d2*waveLength+(time*5.))*0.5+0.5 * (((d1 - 0.5) * 2.) + 0.5);
	float c = d1 > 0.99 || d2 > 0.99 ? 1. : 0.;
	c + wave1*wave2;
	gl_FragColor = vec4(c + wave1*wave2,c,c,1.);

}