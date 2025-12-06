// 1st raymarch by jvb. 

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float pln0(vec3 p)
{
	vec3 n = normalize(vec3(0,-1.0,0));
	return -dot(n, p) + 0.5;
}
float sph0(vec3 p)
{
	p -= vec3(0,sin(time)*0.0-0.0,0);
	float d = length(p) - 0.5 + sin(p.x*12.0+time*2.0)*1.1* sin(p.y*11.0+time)*0.32*sin(p.z*03.0)*0.5; 
	return d; 
}

	
float scene(vec3 p)
{
	//float d1 =  sin(p.x*1.0) + sin(p.y*1.0) + sin(p.z*1.0) - 0.5; 
	//float d2 =  length(p) - 0.5; 
	//return min(d1,-d2);

	return min(sph0(p),pln0(p));
}
vec3 get_normal(vec3 p)
{
	vec3 eps = vec3(0.001,0,0);
	
	float nx = scene(p + eps.xyy) - scene(p - eps.xyy);
	float ny = scene(p + eps.yxy) - scene(p - eps.yxy);
	float nz = scene(p + eps.yyx) - scene(p - eps.yyx);
	
	return normalize(vec3(nx,ny,nz));
}
float random(vec2 p)
{
	return fract(sin(p.x*123.2323+p.x*23.23+p.y*32.2332)*43632.232313);
}

float rm(out vec3 pos, in vec3 ro, in vec3 rd)
{
	pos = ro; 
	float dist = 0.0; 
	for (int i = 0; i < 64; i++) {
		float d = scene(pos);
		
		pos += d*rd;	
		dist += d; 
	}
	return dist; 
}

float softshadow(out vec3 pos, in vec3 ro, in vec3 rd)
{
	pos = ro; 
	float dist = 0.0; 
	for (int i = 0; i < 5; i++) {
		float d = scene(pos);
		pos += d*rd;	
		dist += d; 
	}
	return dist; 
}


void main( void ) {

	float aspect = resolution.x/resolution.y; 
	vec2 p = 2.0*( gl_FragCoord.xy / resolution.xy ) - 1.0;
	p.x *= aspect;

	
	
	vec3 ro = vec3(mouse.x*0.0,mouse.y*0.0,-1);
	vec3 rd = normalize(vec3(p.x,p.y,1.0));
	vec3 pos; 
	float dist = rm(pos, ro, rd);
	
	vec3 col = vec3(0);
	
	vec3 lightpos = vec3(0,2,0);
	vec3 n = get_normal(pos);
	vec3 l = normalize(lightpos - pos);
	float dot = dot(n, l);
	
	vec3 sp; 
	float shade = 1.0*softshadow(sp, pos+n*0.04, l);
	shade = clamp(shade,0.0,1.0);
	
	vec3 rp; 
	float refl = rm(rp, pos+n*0.1, reflect(rd, n));
	refl = smoothstep(refl,0.0,1.0)*0.1;
	
	col = vec3(dot,0,0)*0.7*shade + 0.05*vec3(1,1,1) + refl*vec3(1,1,1)*0.1;
	col = col*(1.0/dist) + 0.0*vec3(0.1,0.1,0.1)*dist*0.1; 
	gl_FragColor = vec4( col, 1.0 );

}