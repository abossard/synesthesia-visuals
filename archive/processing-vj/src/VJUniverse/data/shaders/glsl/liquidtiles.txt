#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

#define PI 3.14159


vec2 noise(vec2 n) {
	vec2 ret;
	ret.x=fract(sin(dot(n.xy, vec2(12.9898, 78.233)))* 43758.5453)*2.0-1.0;
	ret.y=fract(sin(dot(n.xy, vec2(34.9865, 65.946)))* 28618.3756)*2.0-1.0;
	return normalize(ret);
}

float perlin(vec2 p) {
	vec2 q=floor(p);
	vec2 r=fract(p);
	float s=dot(noise(q),p-q);
	float t=dot(noise(vec2(q.x+1.0,q.y)),p-vec2(q.x+1.0,q.y));
	float u=dot(noise(vec2(q.x,q.y+1.0)),p-vec2(q.x,q.y+1.0));
	float v=dot(noise(vec2(q.x+1.0,q.y+1.0)),p-vec2(q.x+1.0,q.y+1.0));
	float Sx=3.0*(r.x*r.x)-2.0*(r.x*r.x*r.x);
	float a=s+Sx*(t-s);
	float b=u+Sx*(v-u);
	float Sy=3.0*(r.y*r.y)-2.0*(r.y*r.y*r.y);
	return a+Sy*(b-a);
}

float func(float x){
	float val = 0.;
	//val += sin(x*100.)*0.1;
	val += perlin(vec2(x*10., time*2.)) * 0.2 * pow(1., -0.4); // random noise
	//val += perlin(vec2(x*4., time*4.)) * 0.15 * pow(1., -0.4); // random noise 2
	//val += fract(-time * (142. / 60.)) * pow(cos(pow(x, 0.5)*PI)*0.5 + 0.5, 2.) * 0.6; // bd
	//val += fract(-time * (142. / 60. / 2.)) * pow(cos(pow(1.-x, 0.9)*PI)*0.5 + 0.5, 2.) * 0.3 * (perlin(vec2(x*100., time*20.))+0.6); // sn
	//val += perlin(vec2(x*10., time*9.)) * 0.1 * (sin(x*PI)); // some shapes
	return val;
}

vec2 complex_mul(vec2 factorA, vec2 factorB){
   return vec2( factorA.x*factorB.x - factorA.y*factorB.y, factorA.x*factorB.y + factorA.y*factorB.x);
}

vec2 complex_div(vec2 numerator, vec2 denominator){
   return vec2( numerator.x*denominator.x + numerator.y*denominator.y,
                numerator.y*denominator.x - numerator.x*denominator.y)/
          vec2(denominator.x*denominator.x + denominator.y*denominator.y);
}

vec2 torus_mirror(vec2 uv){
	return vec2(1.)-abs(fract(uv*.5)*2.-1.);
}

void main( void ) {
	vec2 aspect = vec2(1.,resolution.y/resolution.x);
	vec2 uv = (gl_FragCoord.xy / resolution.xy - 0.5)*aspect;
	float mouseW = -atan((mouse.y - 0.5), (mouse.x - 0.5));
	vec2 mousePolar = vec2(-cos(mouseW), sin(mouseW));
	vec2 offset = 0.5 + complex_mul((mouse-0.5)*vec2(-1.,1.)*aspect, mousePolar)*aspect*8. ;
	
	//vec2 p = torus_mirror(complex_div(mousePolar*vec2(0.825), uv) - offset).yx;

	vec2 p = (gl_FragCoord.xy / resolution.xy);
	p.y -= 0.5;
	gl_FragColor = vec4(vec3(0.1 + p.y, 0.3, 0.8),0.);
	float val = func(p.x);
	
	gl_FragColor += vec4(vec3(0.5, 1.2, 2.0)*pow(clamp((1.-abs(p.y-val)*30.), 0., 1.), 30.), 0.);
	gl_FragColor += vec4(vec3(pow(clamp(-(p.y-val), 0., 1.), 0.5) * vec3(1.2, 1.2, 1.9)),1.0);
	gl_FragColor += vec4(vec3(1., 1., 1.)*(pow(1.-sin(mod(p.x,0.1)*PI*10.),28.)+pow(1.-sin(mod(p.y,0.1)*PI*10.),28.)),1.);
}