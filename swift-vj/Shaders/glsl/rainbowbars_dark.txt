// bars - thygate@gmail.com

// rotation and color mix modifications by malc (mlashley@gmail.com)

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

vec2 position;
vec4 color;

float c = cos(time/2.0);
float s = sin(time/2.0);
mat2 R = mat2(c,-s,s,-c);

float barsize = 0.15;
float barsangle = 1.0;

vec4 mixcol(float value, float r, float g, float b)
{
	return vec4(value * r, value * g, value * b, value);
}

void bar(float pos, float r, float g, float b)
{
	 if ((position.y <= pos + barsize) && (position.y >= pos - barsize))
		color = (color * color.a) + mixcol(1.0 - abs(pos - position.y) / barsize, r, g, b);
}

void main( void ) {

	position = ( gl_FragCoord.xy / resolution.xy );
	position = position * vec2(2.0) - vec2(1.0);
	position = position * R; 		
		
	color = vec4(0., 0., 0., 0.);
	float t = mod(time * 0.1, 10.) + time;

	bar(sin(t), 			1.0, 0.0, 0.0);
	bar(sin(t+barsangle/6.*2.), 	1.0, 1.0, 0.0);
	bar(sin(t+barsangle/6.*4.),  0.0, 1.0, 0.0);
	bar(sin(t+barsangle/6.*6.),  0.0, 1.0, 1.0);
	bar(sin(t+barsangle/6.*8.),  0.5, 0.0, 1.0);
	bar(sin(t+barsangle/6.*10.),  1.0, 0.0, 1.0);
	
	gl_FragColor = color;

}