#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


float round(float f)
{
	if (fract(f) > 0.5)
		return floor(f) + 1.0;
	else return floor(f);
}

bool isDot(vec2 position)
{
	vec2 dotCenter =  vec2(round(position.x / 100.0) * 100.0 + sin(position.x / 50.0) * 10.0,
			       round(position.y / 100.0) * 100.0 + cos(position.y / 20.0) * 10.0);

	if (length(position - dotCenter) < 24.0)
		return true;
	return false;
}

void main( void ) {

	vec2 position = ( gl_FragCoord.xy);
	position.x += time * 10.0;
	position.y += sin(time) * 20.0;

	float color = cos(length(time));

	vec4 dotColor = vec4( vec3( color, color * 0.5, sin( color + time / 3.0 ) * 0.75 ), 1.0 );
	vec4 noDotColor = vec4(1.0 - dotColor.r, 1.0 - dotColor.g, 1.0 - dotColor.b, 1.0);
	
	gl_FragColor = isDot(position) ? dotColor : noDotColor;
}