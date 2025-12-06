#ifdef GL_ES
precision mediump float;
#endif
// dashxdr was here 20120228


// MK Color mod for more awesome

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


float rainbow(float x)
{
	x=fract(0.16666 * abs(x));
	if(x>0.5) x = 1.0-x;
	return smoothstep(.166666, .333333, x);
}

void main( void ) {

	vec2 position = ( 2.0*gl_FragCoord.xy - resolution) / resolution.xx;

	vec3 color = vec3(0.0);

	float r = length(position);
	float a = atan(position.y, position.x);

	float b = (a)*3.0/3.14159;
	color = vec3(rainbow(b+time+3.0), rainbow(b+time+1.0), rainbow(b+time+5.0));

	float t = .5*(1.0 + cos(a + 40.0 * r * (1.0 + sin(a*20.0)*.1) - time*3.0) * (5.0 / (r+5.0)));
	t = (t<.5) ? 0.0 : 1.0;
	gl_FragColor.rgba = vec4(color*t, 1.0);

}