#ifdef GL_ES
precision mediump float;
#endif
#define PI 3.141592653589793

// burl figure

uniform float time;

void main()
{
	vec2 p=.005*gl_FragCoord.xy;
	for(int i=1;i<50;i++)
	{
		vec2 newp=p;
		newp.x+=0.6/float(i)*sin(float(i)*p.y+time/20.0+0.3*float(i))+400./20.0;		
		newp.y+=0.6/float(i)*sin(float(i)*p.x+time/20.0+0.3*float(i+10))-400./20.0+15.0;
		p=newp;
	}
	vec3 c =vec3(sin(time+p.y+p.x-PI*vec3(0,2,4)/(4.+1.*sin(time)))*0.3+0.5);
	gl_FragColor=vec4(c, 1.0);
}
