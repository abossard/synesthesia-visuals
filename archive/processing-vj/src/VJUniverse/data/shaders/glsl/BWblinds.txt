#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );// + mouse / 121.0;
	vec2 pos = gl_FragCoord.xy;
	float color = 1.0;
	color += sin( position.x * cos( 1.0 ) * 1.0 ) + cos( position.y * cos( 110.0 ) * 1.0 );
	//color += sin( position.y * sin( time / 10.0 ) * 40.0 ) + cos( position.x * sin( time / 5.0 ) * 10.0 );
	//color += sin( position.x * sin( time / 5.0 ) * 1.0 ) + sin( position.y * sin( time / 5.0 ) * 8.0 );
	//color *= sin( time / 100.0 ) * 10.0;

	float d = 0.10;
	color = sin((position.x)*3.14*2.0*sin(time/2.0)) + sin(position.y*3.14*2.0);
	color += tan(position.y*3.14*20.0);
	
	color+= 1.0;
	color*= 1.5;
	gl_FragColor = vec4( vec3( color, color, color ), 1.0);
	//gl_FragColor = vec4(color);

}