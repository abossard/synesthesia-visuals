#ifdef GL_ES
precision highp float;
#endif

// Simple Mandelbulb - by @SyntopiaDK
// (The camera code was taken from an example by @mrdoob)
// (Bloom + Vignette by @AlteredQ)

uniform vec2 resolution;
uniform float time;
uniform vec2 mouse;
uniform sampler2D backbuffer;

float PI=3.14159265;
#define Power 8.0
#define Bailout 4.0

float rand(vec2 co){
	// implementation found at: lumina.sourceforge.net/Tutorials/Noise.html
	return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void powN1(inout vec3 z, float r, inout float dr) {
	// extract polar coordinates
	float theta = acos(z.z/r);
	float phi = atan(z.y,z.x);
	dr =  pow( r, Power-1.0)*Power*dr + 1.0;
	
	// scale and rotate the point
	float zr = pow( r,Power);
	theta = theta*Power;
	phi = phi*Power;
	
	// convert back to cartesian coordinates
	z = zr*vec3(sin(theta)*cos(phi), sin(phi)*sin(theta), cos(theta));
}

// Compute the distance from `pos` to the Mandelbox.
float DE(vec3 pos) {
	vec3 z=pos;
	float r;
	float dr=1.0;
	r=length(z);
	for(int i=0; (i < 5); i++) {
		powN1(z,r,dr);
		z+=pos;
		r=length(z);
		if (r>Bailout) break;
	}
	
	return 0.5*log(r)*r/dr;
}

// Uses the soft-shadow approach by Quilez:
// http://iquilezles.org/www/articles/rmshadows/rmshadows.htm
float shadow(vec3 pos, vec3 sdir, float eps) {
	float totalDist =2.0*eps;
	float s = 1.0; // where 1.0 means no shadow!
	for (int steps=0; steps<30; steps++) {
		vec3 p = pos + totalDist * sdir;
		float dist = DE(p);
		if (dist < eps)  return 1.0;
		s = min(s, 4.0*(dist/totalDist));
		totalDist += dist;
	}
	return 1.0-s;
}


vec3 DEColor(vec3 pos) {
	vec3 z=pos;
	float r;
	float dr=1.0;
	r=length(z);
	float minR =  1000.0;
	for(int i=0; (i < 2); i++) {
		powN1(z,r,dr);
		z+=pos;
		r=length(z);
		minR = min(r,minR);
		if (r>Bailout) break;
	}
	float i = minR*minR*minR*minR*0.70;
	i*=(0.8+0.2*rand(time+pos.xy));
	return vec3(clamp(i*i,0.0,1.0));
	
}


void main(void){
	vec2 vPos=-1.0+2.0*gl_FragCoord.xy/resolution.xy;
	
	//Camera animation
	vec3 vuv=vec3(0,1,0);//Change camere up vector here
	vec3 vrp=vec3(0,0,0); //Change camere view here
	float mx=mouse.x*PI*2.0;
	float my=mouse.y*PI/2.01;
	vec3 prp=vec3(cos(my)*cos(mx),sin(my),cos(my)*sin(mx))*2.0; //Trackball style camera pos
	
	
	//Camera setup
	vec3 vpn=normalize(vrp-prp);
	vec3 u=normalize(cross(vuv,vpn));
	vec3 v=cross(vpn,u);
	vec3 vcv=(prp+vpn);
	vec3 scrCoord=vcv+vPos.x*u*resolution.x/resolution.y+vPos.y*v;
	vec3 scp=normalize(scrCoord-prp);
	
	//Raymarching
	const vec3 e=vec3(0.00001,0,0);
	const float maxd=4.0; //Max depth
	float s=0.0;
	vec3 c,p,n;
	
	float f=0.80;
	float minDE = 0.;
	for(int i=0;i<46;i++){
		f+=s;
		p=prp+scp*f;
		s=DE(p);
		minDE = float(i);
		if (abs(s)<.00065||f>maxd) break;
		
	}
	minDE*=(0.5+0.5*rand(time+p.xy));
	
	if (f<maxd){
		n=normalize(
			vec3(s-DE(p-e.xyy),
				s-DE(p-e.yxy),
				s-DE(p-e.yyx)));
		c = DEColor(p);
		//c.yz = mix(c.yz, n.yz, 0.3);
		vec3 dir = normalize(prp-p);
		vec3 spotDir = vec3(cos(time/5.0),sin(time/5.0),sin(time/4.0));
		// Calculate perfectly reflected light
		vec3 r = spotDir - 2.0 * dot(n, spotDir) * n;
		float s = max(0.0,dot(dir,-r));
		float diffuse = max(0.0,dot(-n,spotDir))*0.60;
		float ambient =1.0;
		float specular =  clamp(pow(s,50.0)*1.1,0.0,0.5);
		float HardShadow = 0.8;
		float eps = 0.001;
		if (HardShadow>0.0) {
			// check path from pos to spotDir
			float shadowStrength = shadow(p+n*eps, -spotDir, eps);
			ambient = mix(ambient,0.0,HardShadow*shadowStrength);
			diffuse = mix(diffuse,0.0,HardShadow*shadowStrength);
			// specular = mix(specular,0.0,HardShadow*f);
			if (shadowStrength>0.0) specular = 0.0; // always turn off specular, if blocked
		}
		
		gl_FragColor=vec4((vec3(1.0)*diffuse+vec3(1.0)*ambient+ specular*vec3(1.0))*vec3(c),1.0);
		
		
		// float b=dot(n,normalize(prp-p));
		// gl_FragColor = mix(vec4((b*c+pow(b,6.0))*(1.0-f*.01),1.0), vec4(c*c,1.0),0.5);
	}
	else {
		float glow = clamp(minDE/46.0,0.0,1.0);
		gl_FragColor=vec4( vec3(0.5+glow*0.5),1.0); //background color
	        if (mod(gl_FragCoord.y,2.0) < 1.0) gl_FragColor = mix( gl_FragColor , vec4(0.0), 0.5 ) ;
	}
	
	// bloom
	
	vec2 position = gl_FragCoord.xy / resolution.xy;
	
	float aspect = resolution.x/resolution.y;
	float dx = 1.0/resolution.x;
	float dy = dx * aspect;
	
	vec4 v0 = texture2D( backbuffer, position );
	vec4 v1 = texture2D( backbuffer, mod ( position + vec2( 0.0, dy ), 1.0 ) );
	vec4 v2 = texture2D( backbuffer, mod ( position + vec2( dx, 0.0 ), 1.0 ) );
	vec4 v3 = texture2D( backbuffer, mod ( position + vec2( 0.0, -dy ), 1.0 ) );
	vec4 v4 = texture2D( backbuffer, mod ( position + vec2( -dx, 0.0 ), 1.0 ) );
	vec4 v5 = texture2D( backbuffer, mod ( position + vec2( dx, dy ), 1.0 ) );
	vec4 v6 = texture2D( backbuffer, mod ( position + vec2( -dx, -dy ), 1.0 ) );
	vec4 v7 = texture2D( backbuffer, mod ( position + vec2( dx, -dy ), 1.0 ) );
	vec4 v8 = texture2D( backbuffer, mod ( position + vec2( -dx, dy ), 1.0 ) );
	
	vec4 ss = v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8;
	gl_FragColor = mix( gl_FragColor * gl_FragColor, 0.125 * ss, 0.5 ) ;
	// vignette
	
	gl_FragColor = vec4( mix( gl_FragColor.rgb, vec3( 0.0 ), dot( position - 0.5, aspect * (position - 0.5)) ), gl_FragColor.a );
}
