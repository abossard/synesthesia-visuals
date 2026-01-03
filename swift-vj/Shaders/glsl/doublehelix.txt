#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
	
void main( void ) {
	vec3 p = vec3(0,-time,-2.);
	vec3 d = normalize(vec3((gl_FragCoord.xy-resolution.xy*.5)/resolution.y*2.,1.));
	d = vec3(d.x,d.y*.8-d.z*.6,d.z*.8+d.y*.6);
	
	
	for (int i = 0; i < 100; i++) {
		vec2 sp = vec2(cos(p.y*2.),sin(p.y*2.));
		float fd = dot(p.xz,sp);
		float fo = dot(vec2(p.z,-p.x),sp);
		float f = length(vec2(length(vec2(p.xz))-1.,max(0.,abs(fo)*.3-.1)))-.02;
		float f2 = length(vec3(fo,max(0.,abs(fd)-1.+.05), (fract(p.y*3.)-.5)*.33))-.05;
			
			
		p += d*min(f*.8,f2*.6);
	}
	float pc = length(p.xz);
	float nc = floor(p.y*3.);
	nc = fract(nc*0.7244)*fract(nc*0.35425);
	vec2 sp = vec2(cos(p.y*2.),sin(p.y*2.));
	float fd = dot(p.xz,sp);
	nc = floor(fract(nc*562.+sign(fd)*.25)*4.);
	float cf = max(0.,1.-pc*1.2);
	
	gl_FragColor = vec4((.8-pc*.5)*(1.-cf)+cf*abs(fract(vec3(.1,.4,.75)+nc*.25)-.5)*2.,1.) ;

}