#ifdef GL_ES
precision mediump float;
#endif

// burl figure

// - trick, use far less iterations!

uniform vec2 resolution;
uniform float time;

const float Pi = 3.14159;

float sinApprox(float x) {
    x = Pi + (2.0 * Pi) * floor(x / (2.0 * Pi)) - x;
    return (4.0 / Pi) * x - (4.0 / Pi / Pi) * x * abs(x);
}

float cosApprox(float x) {
    return sinApprox(x + 0.5 * Pi);
}

const int steps = 7;
const int stepscale = 3;
const float colorscale = 10.0;

void main()
{
	vec2 p=(2.0*gl_FragCoord.xy-resolution)/max(resolution.x,resolution.y);
	vec3 col;
	for(int i=1;i<=steps;i++)
	{
		vec2 newp=p;
		newp.x+=0.6/float(i)*sin(float(i*stepscale)*p.y+time/10.0+0.3*float(i))+400./20.0;		
		newp.y+=0.6/float(i)*sin(float(i*stepscale)*p.x+time/10.0+0.3*float(i+10))-400./20.0+15.0;
		p=newp;
		
		if(i>=(steps-2)) {
			float level = sin(length(p)*colorscale)*0.5+0.5;
			col[i-(steps-2)] = level;
		}
	}
	gl_FragColor=vec4(col, 1.0);
}
