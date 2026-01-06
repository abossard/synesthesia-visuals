#ifdef GL_ES
precision mediump float;
#endif

// domain map version forked from http://glsl.heroku.com/e#5153.2

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
uniform sampler2D backbuffer;


vec2 complex_mul(vec2 factorA, vec2 factorB){
	
	int i=1;//test
   return vec2( factorA.x*factorB.x - factorA.y*factorB.y, factorA.x*factorB.y + factorA.y*factorB.x);
}

vec2 torus_mirror(vec2 uv){
	return vec2(1.)-abs(fract(uv*.5)*2.-1.);
}

float circle(vec2 uv, float scale){
	return clamp( 1. - length((uv-0.5)*scale), 0., 1.);
}

float sigmoid(float x) {
	return 2./(1. + exp2(-x)) - 1.;
}

float smoothcircle(vec2 uv, float radius, float sharpness){
	return 0.5 - sigmoid( ( length( (uv - 0.5)) - radius) * sharpness) * 0.5;
}

float border(vec2 domain, float thickness){
   vec2 uv = fract(domain-vec2(0.5));
   uv = min(uv,1.-uv)*2.;
   return clamp(max(uv.x,uv.y)-1.+thickness,0.,1.)/(thickness);
}

void main( void ) {
	vec2 aspect = vec2(1.,resolution.y/resolution.x);
	vec2 uv = 0.5 + (gl_FragCoord.xy * vec2(1./resolution.x,1./resolution.y) - 0.5)*aspect;
	float mouseW = atan((mouse.y - 0.5)*aspect.y, (mouse.x - 0.5)*aspect.x);
	vec2 mousePolar = vec2(sin(mouseW), cos(mouseW));
	vec2 offset = (mouse - 0.5)*4.;
	offset =  - complex_mul(offset, mousePolar) +time*0.02;
	
	float filter = smoothcircle(uv, 0.12, 24.);
	vec2 uv_distorted = torus_mirror(0.5 + complex_mul(((uv - 0.5)*mix(2., 16., filter)), mousePolar) + offset);
	
	filter = smoothcircle(uv_distorted, 0.12, 24.);
	vec2 uv_distorted2 = torus_mirror(0.5 + complex_mul(((uv_distorted - 0.5)*mix(2., 16., filter)), mousePolar) + offset);
	
	filter = smoothcircle(uv_distorted2, 0.12, 24.);
	vec2 uv_distorted3 = torus_mirror(0.5 + complex_mul(((uv_distorted2 - 0.5)*mix(2., 16., filter)), mousePolar) + offset);
	
	filter = smoothcircle(uv_distorted3, 0.12, 24.);
	vec2 uv_distorted4 = torus_mirror(0.5 + complex_mul(((uv_distorted3 - 0.5)*mix(2., 16., filter)), mousePolar) + offset);
	
	gl_FragColor.zw = vec2(0);
	gl_FragColor.xy = uv_distorted3; // domain map, third iteration
	
	
	gl_FragColor = mix(gl_FragColor, vec4(0), vec4(border(uv_distorted2, 0.125)*0.5)); // blend domain borders from second iteration first
	
	gl_FragColor = mix(gl_FragColor, vec4(1), vec4(border(uv_distorted, 0.125))); // blend domain borders from first iteration
	
	//gl_FragColor = vec4(circle(uv, 5.)* 0.5); // seed
	//gl_FragColor += texture2D(backbuffer, uv_distorted)*mix(1., 0.6, filter); // that would be feedback from the first iteration
}