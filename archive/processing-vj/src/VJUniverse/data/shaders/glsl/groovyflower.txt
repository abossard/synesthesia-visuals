#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) - vec2(0.5); // + mouse / 4.0;

	float radius = 1.0 - sqrt(position.x * position.x + position.y * position.y) * 4.0;
	float angle = 5.0 * atan(position.y, position.x);
	float r = sin(radius + sin(angle + sin(4.0*radius + angle + time))) * 1.0;
	float g = sin(radius + time) + sin(angle + sin(5.0*radius)) * 1.0;
	float b = sin(sin(3.0 * radius + angle) + time * 2.0 + angle) * 1.0;
	if (r < 0.01) r = 1.0;
	if (g < 0.01) g = 1.0;
	if (b < 0.01) b = 1.0;
	gl_FragColor = vec4( vec3(r,g,b)*0.8, 1.0 );

}