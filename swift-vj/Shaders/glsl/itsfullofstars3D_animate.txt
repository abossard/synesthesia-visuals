#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;
uniform vec2 mouse;
vec4 colour(float c)
{
	c*=13.0;
	vec3 res = vec3(0.0,0.0,0.0);
	res += smoothstep(1.0,2.0,c) * vec3(1.0,3.0,31.0)/255.0;
	res += smoothstep(2.0,3.0,c) * vec3(0.0,0.0,22.0)/255.0;
	res += smoothstep(3.0,4.0,c) * vec3(27.0,-1.0,25.0)/255.0;
	res += smoothstep(4.0,5.0,c) * vec3(52.0,0.0,32.0)/255.0;
	res += smoothstep(5.0,6.0,c) * vec3(63.0,1.0,23.0)/255.0;
	res += smoothstep(6.0,7.0,c) * vec3(38.0,0.0,-30.0)/255.0;
	res += smoothstep(7.0,8.0,c) * vec3(48.0,0.0,-57.0)/255.0;
	res += smoothstep(8.0,9.0,c) * vec3(23.0,70.0,-15.0)/255.0;
	res += smoothstep(9.0,10.0,c) * vec3(1.0,100.0,50.0)/255.0;
	res += smoothstep(10.0,11.0,c) * vec3(1.0,71.0,58.0)/255.0;
	res += smoothstep(11.0,12.0,c) * vec3(-15.0,10.0,64.0)/255.0;
	res += smoothstep(12.0,13.0,c) * vec3(3.0,1.0,33.0)/255.0;
	return vec4(res,1.0);
}
float periodic(float x,float period,float dutycycle)
{
	x/=period;
	x=abs(x-floor(x)-0.8)-dutycycle*0.5;
	return x*period;
}

float pcount(float x,float period)
{
	return floor(x/period);
}

float distfunc(vec3 pos)
{
	vec3 gridpos=pos-floor(pos)-0.9;
	float r=length(pos.xy);
	float a=atan(pos.y,pos.x);
	a+=time*0.9*sin(pcount(r,3.0)+1.0)*sin(pcount(pos.z,1.0)*13.73);
	return min(max(max(
		periodic(r,3.0,0.2),
		periodic(pos.z,1.0,0.7+0.3*cos(time/3.0))),
		periodic(a*r,3.141592*2.0/6.0*r,0.7+0.3*cos(time/3.0))),0.25);
}

void main()
{
	vec2 coords=(2.0*gl_FragCoord.xy-resolution)/max(resolution.x,resolution.y);

	vec3 ray_dir=normalize(vec3(coords,1.0+0.0*sqrt(coords.x*coords.x+coords.y*coords.y)));
	vec3 ray_pos=vec3(32.0*pow(0.5-mouse.x, 1.),32.0*(0.5-mouse.y),time*1000.0*pow(0.5-mouse.x,2.0)*pow(0.5-mouse.y,2.0));
	float a=cos(time)*0.0*0.4;
	ray_dir=ray_dir*mat3(
		cos(a),0.0,sin(a),
		0.0,1.0,0.0,
		-sin(a),0.0,cos(a)
	);

	float i=192.0;
	for(int j=0;j<192;j++)
	{
		float dist=distfunc(ray_pos);
		ray_pos+=dist*ray_dir;

		if(abs(dist)<0.001) { i=float(j); break; }
	}

	float c=i/192.0;
	gl_FragColor=colour(c + mouse.x);
}
