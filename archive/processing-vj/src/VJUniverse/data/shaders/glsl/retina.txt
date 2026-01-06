#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	
	vec2 m = mouse;
	vec2 op = vec2(gl_FragCoord.x,gl_FragCoord.y);
	float dx = ((resolution.x)/2.0) - op.x + m.x*5.0;
	float dy = ((resolution.y)/2.0) - op.y + m.y*5.0;
	float k = (sin(time*0.4)+1.0)*0.5;
	float d = (dx*dx + dy*dy)*k;
	float t = time;//*mouse.x*0.01;
		
	float r = (sin(t+d*0.029)+1.0)*0.5;
	float g = (sin(t*1.4 +d*0.03)+1.0)*0.5;
	float b = (sin(t*10.0 +d*0.03)+1.0)*k;
	
	vec3 rgb = vec3(r,g,b);
	

	
	gl_FragColor = vec4( rgb, 1.0 );

}