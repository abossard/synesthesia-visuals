#ifdef GL_ES
precision mediump float;
#endif
 
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

#define PI 3.1415927
#define PI2 (PI*2.0)

// http://glsl.heroku.com/e#7109.0 simplified by logos7@o2.pl

void main(void)
{
	vec2 position = 100.0 * ((2.0 * gl_FragCoord.xy - resolution) / resolution.xx);

	float r = length(position);
	float a = atan(position.y, position.x);
	float d = r - a + PI2;
	float n = PI2 * float(int(d / PI2));
	float k = a + n;
	float rand = sin(floor(0.07 * k * k + time));

	gl_FragColor.rgba = vec4(fract(rand*vec3(10.0, 1000.0, 100000.0)), 1.0);
}