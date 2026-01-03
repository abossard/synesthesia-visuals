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
	
	// radius+=0.7/(1.0+abs(sin(time+2.5*atan(position.y-center.y, position.x-center.x))));
	radius*=1.0-0.1/(0.8+0.1/(0.9-abs(sin(time-4.5*atan(position.y-center.y, position.x-center.x)))));
	
	return length < radius ? sin(pow(length / radius, 40.0) * 3.0 + 0.3) : 0.0;
}

void main(void)
{
	vec2 position = 4.0*(gl_FragCoord.xy - 0.5 * resolution) / resolution.y;
	
	float r = circle(vec2(sin(time*1.01), cos(time*0.98)), 1.0+sin(time*.9), position);
	float g = circle(vec2(cos(time*0.94), sin(time*0.97)), 1.0+sin(time*.8), position);
	float b = circle(vec2(sin(time*0.93), sin(time*0.99)), 1.0+sin(time*.7), position);
	float m = circle(vec2(-cos(time*1.02), -sin(time*0.96)), 1.0+sin(time*.6), position);
	float y = circle(vec2(-sin(time*0.92), -sin(time*1.03)), 1.0+sin(time*.5), position);
	float w = circle(vec2(-sin(time*1.05), cos(time*0.95)), 1.0+sin(time)*.4, position);
	float o = circle(vec2(cos(time*0.91), -cos(time*1.04)), 1.0+sin(time)*.3, position);
	
	gl_FragColor = vec4(r+y+m+o+w, g+y+0.5*o+w, b+m+w, 1.0);
}