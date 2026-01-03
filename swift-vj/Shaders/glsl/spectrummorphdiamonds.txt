#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) + mouse / 4.0;
	
	vec3 couleur = vec3(02.0, 1.5, 0.0) * sin(position.x * 10.0) * cos(position.y * 10.0);
	
	vec3 couleur2 = vec3(12.0, 12.0, 12.0) * sin(position.y * 10.0) * cos(position.x * 10.0);
	
	vec3 couleur3 = vec3(1., 2.0, .0) * sin(position.y * 10.0) * cos(position.x * 15.0);
	
	gl_FragColor = vec4 (couleur + couleur3 + couleur2 * sin(time * 2.0), 1.0);

	
}