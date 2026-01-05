// i'll get them hexagoms one day
// this is proper ugly
// @M

// oh oh - now lets combine the two hexagon approaches :-)

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


float
rand(float x)
{
	return mod(sin(x*119.)*79., 1.);
}

float hex(vec2 p) {
	p.x *= 0.57735*2.0;
	p.y += mod(floor(p.x), 2.0)*0.5;
	p = abs((mod(p, 1.0) - 0.5));
	return abs(max(p.x*1.5 + p.y, p.y*2.0) - 1.0);
}

float
color(vec2 p)
{
	vec2 r, q;
	
	p = p / vec2(sqrt(3.)/2., 1.5);
	r = floor(p);
	p = vec2(abs(mod(p.x+r.y, 2.)-1.), mod(p.y, 1.));
	if(p.x/3. - p.y > 0.)
		r.y--;
	r.x = floor((r.x+mod(r.y,2.))/2.);	
	return rand(r.x*17.+r.y);
}

void
main(void)
{
	vec2 p = gl_FragCoord.xy / resolution.x + vec2(sin(abs(mod(time, 2.)-1.)*sin(time/2.)/4.), sin(time/2.)*sin(time/15.));
	float c = 0.;
	p *= 20.0; // scale
	c = color(p)*smoothstep(0.0, 0.1, hex(p.yx*0.57735 + vec2(0.72,0.5))); // why 0.72... bah - align by eye, close enough
	gl_FragColor = vec4(c, c, c, 1.);
}