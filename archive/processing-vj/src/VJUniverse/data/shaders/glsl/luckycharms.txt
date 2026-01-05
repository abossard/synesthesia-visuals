#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) - vec2(0.5); // + mouse / 4.0;

	float radius = 1.0 - sqrt(position.x * position.x + position.y * position.y) * 4.0;
	float angle = 4.0 * atan(position.y, position.x);
	float r = sin(radius + sin(angle + sin(2.0*radius + angle + time))) * 4.0;
	float g = sin(radius + time) + sin(angle + sin(2.0*radius)) * 4.0;
	float b = sin(radius + sin(angle + time) + sin(angle)) * 4.0;
	if (r < 0.5) r = 0.5;
	if (g < 0.2) g = 0.2;
	if (b < 0.6) b = 0.6;
	gl_FragColor = vec4( vec3(r,g,b), 1.0 );

}