// LEDs, https://twitter.com/#!/baldand/status/160081733180604417
// Originally designed to fit in a tweet with just a bit of boilerplate
#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main (void) {
	vec2 v = (gl_FragCoord.xy / resolution.xy) + mouse / 4.0;
	float w, x, z = 0.0;
	vec2 u;
	vec3 c;
	v *= 10.;
	u = floor(v) * 0.1 + vec2(20.0, 11.0);
	u = u * u;
	x = fract(u.x * u.y * 9.1 + time);
	x *= (1.0 - length(fract(v) - vec2(0.5, 0.5)) * (2.0 + x));
	c = vec3(v * x, x);
	gl_FragColor = vec4(c,1.);
}