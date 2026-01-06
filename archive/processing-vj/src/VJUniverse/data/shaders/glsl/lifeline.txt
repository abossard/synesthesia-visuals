// by @DonMilham

#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 resolution;

void main( void ) {

	vec2 position = gl_FragCoord.xy / resolution.xy;
	float t = time + position.x;

	vec2 o, off;

	o = 1.0 - abs(2.0 * fract(15.0 * position) - 1.0);
	off = .5 * o + .5 * pow(o, vec2(7));
	float grid2 = .5 * max(off.x, off.y);

	o = 1.0 - abs(2.0 * fract(1.0 * position) - 1.0);
	off = .5 * o + .5 * pow(o, vec2(11));
	float grid1 = .5 * max(off.x, off.y);

	vec4 grid = vec4(0, .5 * grid2 + grid1, 0, 1);

	float f = clamp(1.0 - abs(position.y - .3 * sin(t*6.0)-.5), 0.0, 1.0);
	float func1 = pow(f, 22.0);

	vec4 func = .7 * vec4(func1, func1, func1, 1);

	gl_FragColor = grid + func;



}