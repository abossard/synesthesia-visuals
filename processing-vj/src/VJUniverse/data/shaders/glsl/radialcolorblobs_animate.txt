#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// modified 2013-03-31 by @hintz

float circle(vec2 center, float radius, vec2 position)
{
	float length = distance(position, center);
	
	radius+=mouse.x*sin(10.0*(time-length)+5.0*atan(position.y-center.y, position.x-center.x));
	
	return length < radius ? sin(pow(length / radius, 4.0) * 3.0 + mouse.y) : 0.0;
}

void main(void)
{
	vec2 position = 2.0*(gl_FragCoord.xy - 0.5 * resolution) / resolution.y;
	
	float r = circle(vec2(sin(time*1.01), cos(time)), 1.0, position);
	float g = circle(vec2(cos(time), sin(time)), 1.0, position);
	float b = circle(vec2(sin(time), sin(time*0.99)), 1.0, position);
	float m = circle(vec2(-cos(time*1.02), -sin(time)), 1.0, position);
	float y = circle(vec2(-sin(time), -sin(time*1.03)), 1.0, position);
	
	gl_FragColor = vec4(r+y+m, g+y, b+m, 1.0);
}