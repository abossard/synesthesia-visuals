#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );

	
	vec3 col = vec3(sin(position.y*20.0));
	
	col.rb *= sin(time+position.x*50.0)*15.0;
	col.gb *= sin(-time*2.0+(6.0+position.x)*100.0)*5.0;
	
	
	if(position.x < 0.1) {
		float x = position.x*10.0;
		col *= vec3(x,x,x);
	} else if(position.x > 0.9) {
		float x = abs(1.0-position.x)*10.0;
		col *= vec3(x,x,x);
	}
	
	
	if(position.x < 0.1) {
		float x = position.x*10.0;
		col *= vec3(x,x,x);
	} else if(position.x > 0.9) {
		float x = abs(1.0-position.x)*10.0;
		col *= vec3(x,x,x);
	}
	
	if(position.y < 0.1) {
		float y = position.y*10.0;
		col *= vec3(y,y,y);
	} else if(position.y > 0.9) {
		float y = abs(1.0-position.y)*10.0;
		col *= vec3(y,y,y);
	}
	
	gl_FragColor = vec4(col,  3.0);
}