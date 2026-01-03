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
	
	col *= ((sin(time/1.5))+0.5)*(cos(distance(mouse.y,position.x)*resolution.x/(3.+position.y*4.*mouse.x)*cos(time/-1.55)));
	col *= ((tan(time/3.))+0.5)*(cos(distance(position.y,mouse.x)*resolution.x/(3.+position.x*4.*mouse.y)*sin(time/-3.1)));
	
	col.r /= sin(time);
	col.g /= cos(time);
	col.b *= sin(distance(vec2(col),vec2(0.5))+time/5.);
	
	
	gl_FragColor = vec4(vec3(col), 1.0 );
}