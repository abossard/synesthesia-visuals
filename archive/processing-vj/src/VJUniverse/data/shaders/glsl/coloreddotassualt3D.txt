#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float rand(vec3 r) { return fract(sin(dot(r.xy,vec2(1.38984*sin(r.z),1.13233*cos(r.z))))*653758.5453); }

float celldist(vec3 ipos,vec3 pos)
{
	vec3 c=ipos+vec3(rand(ipos),rand(ipos+0.1),rand(ipos+0.2));
	return length(c-pos)-(rand(ipos+0.3)*0.2+0.2)*sin(c.x+c.z+time);
}

float distfunc(vec3 pos)
{
	vec3 ipos=floor(pos)-0.5;

	float d1=celldist(ipos+vec3(0.0,0.0,0.0),pos);
	float d2=celldist(ipos+vec3(0.0,0.0,1.0),pos);
	float d3=celldist(ipos+vec3(0.0,1.0,0.0),pos);
	float d4=celldist(ipos+vec3(0.0,1.0,1.0),pos);
	float d5=celldist(ipos+vec3(1.0,0.0,0.0),pos);
	float d6=celldist(ipos+vec3(1.0,0.0,1.0),pos);
	float d7=celldist(ipos+vec3(1.0,1.0,0.0),pos);
	float d8=celldist(ipos+vec3(1.0,1.0,1.0),pos);

	return min(min(min(d1,d2),min(d3,d4)),min(min(d5,d6),min(d7,d8)));
}

void main()
{
	vec2 coords=(2.0*gl_FragCoord.xy-resolution.xy)/max(resolution.x,resolution.y);

	vec3 ray_dir=normalize(vec3(coords,1.0-0.0*sqrt(coords.x*coords.x+coords.y*coords.y)));
	vec3 ray_pos=vec3(0.0,-1.0,time*1.0);

	float a=0.0;
	ray_dir=ray_dir*mat3(
		cos(a),0.0,sin(a),
		0.0,1.0,0.0,
		-sin(a),0.0,cos(a)
	);

	float i=64.0;
	for(int j=0;j<64;j++)
	{
		float dist=distfunc(ray_pos);
		ray_pos+=dist*ray_dir;

		if(abs(dist)<0.001) { i=float(j); break; }
	}

	float c=i/64.0;
	gl_FragColor=vec4(vec3(1.0-c,  sin(2.*time)-c , cos(time* 4.)-.2-c),1.0);
}
