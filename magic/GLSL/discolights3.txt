#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );

	vec3 col = vec3(0.5, 0.5, 0.5);
	
	col += position.x;
	
	col *= ((sin(time*10.0))+0.5)*(sin(position.x*50.0));
	col *= ((tan(time*10.0))+0.5)*(sin(position.y*25.0));
	
	col.r /= sin(time);
	col.g /= cos(time);
	
	
	gl_FragColor = vec4(vec3(col), 1.0 );
}