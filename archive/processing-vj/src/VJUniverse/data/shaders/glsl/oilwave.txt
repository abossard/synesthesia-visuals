// by rotwang, some scrolling shapes for Krysler
#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


float Krysler_623(vec2 p) {

	p *= p;
	float sy = sin(p.y/4.0);
	p.y = mix(1.0/atan(p.x,p.y),cos(p.x+time),mod(p.y,16.0));
	p.y *= p.y;
	float shade = ( sin( p.x + time ) );
	shade = min(p.x,p.y);

	return shade;
}

vec3 Krysler_623_clr(vec2 p) {

	float shade = Krysler_623(p);
	vec3 clr_a = vec3(shade*0.2, shade*0.66, shade);
	vec3 clr_b = vec3(shade*0.2, shade*0.5, shade*0.6);
	vec3 clr = clr_a*p.y*0.5; //  + clr_b*(1.0-p.y)*0.25;
	
	clr += clr_b*(1.0-p.y);
	return clr;
}

void main( void ) {

	float aspect = resolution.x / resolution.y;
	vec2 unipos = ( gl_FragCoord.xy / resolution );
 	vec2 pos = unipos*2.0-1.0;//bipolar
	pos.x *= aspect;

	vec3 clr = Krysler_623_clr(pos*3.0);

	gl_FragColor = vec4(clr,  1.0);
}