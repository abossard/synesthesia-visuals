#ifdef GL_ES
precision mediump float;
#endif

// @RicoTweet 
// If you want to learn more about how to make Mandelbrot sets watch http://youtu.be/t75gXyWJNpA 

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
 
//const vec2 c = vec2(.0, .0);
//const vec2 c = vec2(.835, -.2321);
//const vec2 c = vec2(0.25, .0);
//const vec2 c = vec2(0.25, .5);
//const vec2 c = vec2(0.4, .6);
//const vec2 c = vec2(0.285, .0);
//const vec2 c = vec2(0.3, .5);

const float MAX = 45.; 
vec2 c = -(mouse - vec2(.5)) * 1.2; 

vec3 hsv = vec3(mod(time * 45., 360.), 1., 0.0); 

vec2 pow2(const vec2 z) { 		
	float a = z.x; 
	float b = z.y; 
	float c = z.x; 
	float d = z.y; 
	
	float r = a*c - b*d; 
	float i = a*d + b*c; 
	return vec2(r,i); 
}

vec2 f(const vec2 z) {
	return pow2(z) + c; 
}

vec3 htr(vec3 hsv) {
	float H = hsv.x; 
	float S = hsv.y; 
	float V = hsv.z;
	float hi = floor(H / 60.);
	float f = H / 60. - hi; 
	float p = V*(1. - S); 
	float q = V*(1. - S * f);
	float t = V*(1. - S * (1. - f));
	
	if(hi == 1.) {
		return vec3(q,V,p);
	} 
	if(hi == 2.) {
		return vec3(p,V,t);
	} 
	if(hi == 3.) {
		return vec3(p,q,V);
	} 
	if(hi == 4.) {
		return vec3(t,p,V);
	} 
	if(hi == 5.) {
		return vec3(V,p,q);
	} 
	return vec3(V,t,p); 
}

void main() {
	float sin = sin(time * .5); 
	float cos = cos(time * .5);  
	vec2 p = (vec2(gl_FragCoord.xy / resolution.xy) - vec2(.5,.5)) * 2. * vec2(resolution.x / resolution.y, 1.0);
	
	vec2 z0 = p; 
	z0.x = p.x*cos - p.y * sin; 
	z0.y = p.x*sin + p.y * cos; 
	
	vec2 z = z0; 
	vec2 znm1; 
	
	for(float i = 0.; i != MAX; i++) {
		znm1 = z; 
		z = f(z); 		 	
		//hsv.x += 360. * i / MAX; 
		hsv.z += i / (MAX * 2.); 
		
		if(length(z-z0) > 3.5) {
			//break; 
			gl_FragColor = vec4(htr(hsv), 1.0) ; 
			return; 
		}		
	}
	 
	hsv += vec3(-180., .0, .0); 
	hsv += vec3(z, 0.); 
	hsv.x = mod(hsv.x, 360.); 
	gl_FragColor = vec4(htr(hsv), 1.0); 
}