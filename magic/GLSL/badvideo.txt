#ifdef GL_ES
precision mediump float;
#endif

#define PI 3.14159

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

vec2 distort(vec2 p,float len)
{
	vec3 foc = vec3(0.,0.,len);
	
	float ax = asin(p.x/(1./distance(vec3(p,0.0),foc)));
	float ay = asin(p.y/(1./distance(vec3(p,0.0),foc)));
	
	return vec2(ax,ay);
}

float triwave(float x)
{
	return 1.0-4.0*abs(0.5-fract(0.5*x + 0.25));
}

float round(float v)
{
	float ret = 0.0;
	if(v - floor(v) >= 0.5) ret = floor(v)+1.0;
	else ret = floor(v);
	return ret;
}

float checkers(vec2 p)
{
	float g = 0.0;
	g = mod(ceil(p.x*16.),2.0);
	g -= mod(ceil(p.y*16.),2.0);
	g = mod(g,2.0);
	g = g* 0.25+0.75;
	return g;
}

void main( void ) {

	vec2 p = ( gl_FragCoord.xy / resolution.xy )-0.5;
	
	vec2 m = mouse-.5;
	
	m = distort(m,.8);

	vec3 color = vec3(0.0);
	
	float d = 1.;
	
	vec2 pd = distort(p,d);
			
	color.r = checkers(pd);
	
	pd = distort(p,d+.01);
			
	color.g = checkers(pd);
	
	pd = distort(p,d+.02);
			
	color.b = checkers(pd);
	
	float b = 1.-distance(p*2.,m*2.);
	b = clamp(b,0.,1.);
	
	color *= vec3(triwave(mod(pd.y*(resolution.y*.25),1.0)));
	color *= vec3(triwave(mod(pd.x*(resolution.x*.25),1.0)))*0.15+.85;
	//color *= vec3(b);

	float darkness = sin((p.x+.5)*PI)*sin((p.y+.5)*PI);
	
	color *= vec3(darkness);
	
	gl_FragColor = vec4(color,0.0);

}