#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy);
	position.y *= 10.0+sin(time);
	position.y -=  5.0;
	

	float color1 = 0.1-abs(sin(time+1.0*3.1415*position.x)-position.y-2.0)*1.0;
	float color2 = 0.1-abs(sin(time+1.0*3.1415*position.x)-position.y-1.0)*1.0;
	float color3 = 0.1-abs(sin(time+1.0*3.1415*position.x)-position.y)*1.0;
	float color4 = 0.1-abs(sin(time+1.0*3.1415*position.x)-position.y)*1.0;
	float color5 = 0.1-abs(sin(time+1.0*3.1415*position.x)-position.y+1.0)*1.0;
	float color6 = 0.1-abs(sin(time+1.0*3.1415*position.x)-position.y+2.0)*1.0;
	
	gl_FragColor = vec4( (vec3( color1, color2, color3 ) * 
			            vec3( color4, color5, color6)), 1.0 );

}