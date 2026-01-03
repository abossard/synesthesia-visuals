// by rotwang, some functions for Krysler

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

const float PI = 3.1415926535;
const float TWOPI = PI*2.0;

float speed = time *0.5;
float aspect = resolution.x / resolution.y;
vec2 unipos = ( gl_FragCoord.xy / resolution );
vec2 pos = vec2( (unipos.x*2.0-1.0)*aspect, unipos.y*2.0-1.0);


float MoireR(vec2 p)
{
	
	float k = 16.0;
        float tt = sin(time*0.7)*PI;
	float ro = 0.1;
	float pm_x = p.x+ro*cos(time);
	float pm_y = p.y+ro*sin(time);
	//float ss = (sin(5.0*time)+2.0);
	float ss = 1.0;
	float k1 = 1024.0*ss+tt;
	float k2 = 1024.0*ss+tt;
	float f = sin(k1*pm_x*pm_x+k2*pm_y*pm_y);
	
	float shade = f; 

	return shade;
}

float MoireG(vec2 p)
{
	
	float k = 16.0;
	float tt = sin(time*0.7)*PI;
	float ro = 0.5;
	float pm_x = p.x+ro*cos(time);
	float pm_y = p.y+ro*sin(time);
	float ss = 1.0;
	float k1 = 1024.0*ss+tt;
	float k2 = 1024.0*ss+tt;
	float f = sin(k1*pm_x*pm_x+k2*pm_y*pm_y);
	
	float shade = f; 

	return shade;
}

float MoireB(vec2 p)
{
	
	float k = 16.0;
	float tt = sin(time*0.7)*PI;
	float ro = 0.7*(1.0+sin(time));
	float pm_x = p.x+ro*cos(time);
	float pm_y = p.y+ro*sin(time);
	float ss = 1.0;
	float k1 = 1024.0*ss+tt;
	float k2 = 1024.0*ss+tt;
	float f = sin(k1*pm_x*pm_x+k2*pm_y*pm_y);
	
	float shade = f; 

	return shade;
}


vec3 Moire_clr(vec2 p, float blades)
{
	float r = length(p);
	
	float shadeR = 1.0*MoireR(p);
	float shadeG = 1.0*MoireG(p);
	float shadeB = 1.0*MoireB(p);
	vec3 clr = vec3(shadeR, shadeG, shadeB);
	return clr;
}






void main( void ) {

	vec3 clr = Moire_clr(pos, 4.0);
	gl_FragColor = vec4( clr, 1.0 );
}