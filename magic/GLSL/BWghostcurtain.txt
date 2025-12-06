#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );// + mouse / 4.0;
	vec2 pos = gl_FragCoord.xy;
	float color = 0.0;

	float d = 0.10;
	color = sin((position.x)*3.14*2.0*sin(time/2.0)) + sin(position.y*3.14*2.0);
	color += sin(position.y*30.0*cos((position.x-0.0)*3.0+30.0));
	
	color+= 1.0;
	color*= 0.5;
	gl_FragColor = vec4( vec3(color), 1.0);

}