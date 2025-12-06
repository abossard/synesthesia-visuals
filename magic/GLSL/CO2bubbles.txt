#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

/*float f(vec2 x) {
	float r = length(x), a = atan(x.y, x.x);
	return r-1. + 0.5*sin(6.*a+2.*r*r*sin(time));
}*/
/*vec4 f(vec2 x) {
	vec2 p = x * abs(sin(time/10.0)) * 50.0;
	float d = sin(length(p)+time), a = sin(mod(atan(p.y, p.x) + time + sin(d+time), 3.1416/3.)*3.), v = a + d, m = sin(length(p)*4.0-a+time);
	return vec4(-v*sin(m*sin(-d)+time*.1), v*m*sin(tan(sin(-a))*sin(-a*3.)*3.+time*.5), mod(v,m), v);
}*/
vec4 f(vec2 x) {
	float d = 1.0;
	float time = time;
	for(int i = 0; i < 23; ++i) {
		vec2 foo = vec2(sin(time*2.5), cos(time*1.5));
		d *= length(foo * 0.8 - x);
		time += 10.0;
	}
	return vec4(d);
}

vec2 grad(vec2 p) {
	vec2 h = vec2(.00001, 0.00001);
	return vec2(f(p+h.xy).w - f(p-h.xy).w, f(p+h.yx).w - f(p-h.yx).w)/(2.0*h.x);
}

vec3 color(vec2 x) {
	vec4 v = f(x);
	vec2 g = grad(x);
	float de = abs(v.w) / length(g);
	float blah = 0.05;
	return vec3(1.0-(blah*0.3, blah, de));
}

void main( void ) {

	vec2 position = gl_FragCoord.xy / resolution.xy * 2. - 1.;
	//position /= 17.0;

	vec3 v = color(position);
	gl_FragColor = vec4( v, 1.0 );

}