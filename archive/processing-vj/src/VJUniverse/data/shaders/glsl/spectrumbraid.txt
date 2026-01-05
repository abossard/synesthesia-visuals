#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );
	
	position.xy = position.yx;
	
	position.x *= 10.0+sin(time*0.25);
	position.x -= 5.0;
	
	float color = 0.0;


	color = 1.0-abs(sin(time*2.0-position.y*3.142*0.5)-position.x)*1.0;
	float color2 = 1.0-abs(sin(time-position.y*3.142*0.75)-position.x-1.0)*1.0;
	float color3 = 1.0-abs(sin(time*3.0-position.y*3.142*1.0)-position.x+1.0)*1.0;
	
	float color4 = 1.0-abs(sin(time*2.5-position.y*1.282*0.5)-position.x+1.0)*1.0;
	float color5 = 1.0-abs(sin(time*3.5-position.y*1.284*0.75)-position.x+1.0)*1.0;
	float color6 = 1.0-abs(sin(time*4.5-position.y*1.284*1.0)-position.x+1.0)*1.0;

	gl_FragColor = vec4( vec3(1,1,1) - vec3( color2, color , color3 ) * vec3( color4, color5, color6 ), 1.0 );
}