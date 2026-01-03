#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) + mouse / 4.0;

	float color = 0.0;
	color += sin( position.x * cos( time / 51.0 ) * 80.0 ) + cos( position.y * cos( time / 15.0 ) * 10.0 );
	color += sin( position.y * sin( time / 10.0 ) * 40.0 ) + cos( position.x * sin( time / 25.0 ) * 40.0 );
	color += sin( position.x * sin( time / 5.0 ) * 10.0 ) + cos( position.y * sin( time / 35.0 ) * 80.0 );
	
	float b = clamp(0.8-distance(position,mouse+mouse/4.0)+0.2*sin(3.*time),0.05,1.);
	gl_FragColor = vec4( vec3( b*color, sin(time)*b*color*sin(5.*time+color*sin(time+color*sin(time+color))), b*sin( color + time / 3.0 ) * 0.75 ), 1.0 );
}