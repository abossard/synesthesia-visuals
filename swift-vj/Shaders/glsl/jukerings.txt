#ifdef GL_ES
precision highp float;
#endif
//tweaks, anony_gt
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

uniform sampler2D backbuffer;

float orbitDistance = 0.00025;
float waveLength = 200.100;

void main( void ) {
	vec2 uv = gl_FragCoord.xy/resolution;

	vec2 p1 = (vec2(sin(time), cos(time))*orbitDistance)-.5;
	vec2 p2 = (vec2(sin(time+3.142), cos(time+3.142))*orbitDistance)+1.75;

	float d1 = 0.1-length(uv +p1);
	float d2 = 0.1-length(uv -p2);

	float wave1 = sin(d1/waveLength+(time*1.))*0.5 + 0.5 * (((d1 - 0.75) * 2.) + 2.5);
	float wave2 = sin(d2*waveLength+(time*5.))*0.5 + 0.5 * (((d1 - 0.25) * 2.) + .5);
	float c = d1 > 0.99 || d2 > 0.995 ? 1. : 0.;
	c + wave1*wave2;
	gl_FragColor = vec4(c + wave1*wave2,c,c,1.);

	// "bumpmapping" @Flexi23
	vec2 d = 1./resolution;
	float dx = texture2D(backbuffer, uv + vec2(-1.,0.)*d).x - texture2D(backbuffer, uv + vec2(1.,0.)*d).x ;
	float dy = texture2D(backbuffer, uv + vec2(0.,-1.)*d).x - texture2D(backbuffer, uv + vec2(0.,1.)*d).x ;
	d = vec2(dx,dy)*resolution/resolution.x*2.;
	gl_FragColor.z = pow(clamp(1.-1.5*length(uv  - vec2(.7*cos(time*.5)+.5,1.*sin(time*.5)+.5) + d),0.,1.),4.0);
	gl_FragColor.y = gl_FragColor.z*.5 + gl_FragColor.x*0.25;

	gl_FragColor *=10.25;

}