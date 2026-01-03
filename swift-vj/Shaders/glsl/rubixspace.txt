#ifdef GL_ES
precision mediump float;
#endif

// T21 : More colors

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float distance(vec3 pos,float r) {
	return length(max(abs(fract(pos)-.5)-r,0.));
}

float rand(vec3 n, float res){
	n = floor(n*res);
	return fract(sin((n.x+n.y*1e2+n.z*1e4)*1e-2)*1e5);
}

float color(vec3 n){
	vec3 f = fract(n)-.5;
	vec3 fa = abs(f);
	float fm = max(max(fa.x,fa.y),fa.z);
	n = floor(n)+.5+f/fm*.2;
	return rand(n, floor(rand(n, 1.)*20.));
}

void main( void ) {
	vec3 lookAt = vec3(0);
	vec3 dir = vec3(0,0,1);//normalize(vec3(mouse.x-.5,mouse.y-.5,1.));
	vec3 left = normalize(cross(dir,vec3(0,1,0)));
	vec3 up = cross(dir,left);
	
	vec3 pos = vec3(0.,0,time*2.);
	
	vec2 screen = (gl_FragCoord.xy-resolution*.5)/resolution.x;
	
	vec3 ray = normalize(dir+left*screen.x+up*screen.y);
	
	float d;
	float s= 0.;
	float r = .15+sin(time*2.)*.1;
	float dsum = 0.;
	
	for (int i = 0; i < 300; i++) {
		d = distance(pos,r);
		dsum += d;
		pos += d*ray;
		if(d<.001) break;		
	}
	
	float c = color(pos);
	gl_FragColor = vec4(vec3(fract(c*16.),fract(c*32.),fract(c*64.))/(1.+dsum*.1),1.);
}