#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float circle (vec2 center, vec2 pos, float mul){
	float d = 1./((center.x-pos.x)*(center.x-pos.x)+(center.y-pos.y)*(center.y-pos.y));
	d /=mul*30.;
	return d;
}

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );

	vec2 circle1 = vec2(sin(time/2.)/2.+0.5, 0.75);
	vec2 circle2 = vec2(0.3, cos (time/2.)/3.+0.3);
	vec2 circle3 = vec2(sin(time/3.)/4.+0.6, cos (time/5.)/3.+0.6);
	
	float color = 0.;
	
	color += circle (circle1, position, (2.+sin(time*2.))*3.5);
	color += circle (circle2, position, (2.+cos(time/2.))*4.);
	color += circle (circle3, position, (2.+sin(time))*3.);
	color += circle (mouse, position, (2.+sin(time)*1.5)*5.);
	
	float step = mouse.x+0.001;
	float colorSimp = floor(color/step)*step;
	
	float verge = 0.1;
	float tresh = 0.003;
	if (color<verge+tresh && color>verge-tresh){
		colorSimp=mouse.x/2.+mouse.y/2.;
	}
	
	gl_FragColor = vec4( vec3( colorSimp*(0.5+sin(time)/2.),  colorSimp*(0.5+cos(time/2.)/2.),  colorSimp*(mouse.x+mouse.y)), 1.0 );
}