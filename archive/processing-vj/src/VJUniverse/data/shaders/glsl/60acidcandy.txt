#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float dtrefle(vec2 p,float b){
	float a=1.57-4.*atan(p.y,p.x);
	float r=length(p);
	return length(p)-2.0*b*sin(a+8.*b);
}

vec2 grad( in vec2 p,float b )
{
    vec2 h = vec2( 0.001, 0.0 );
    return vec2(dtrefle(p+h,b) - dtrefle(p-h,b),
                 dtrefle(p+h.yx,b) - dtrefle(p-h.yx,b) )/(2.0*h.x);
}


vec2 color( in vec2 p,float b )
{
    float v = dtrefle(p,b );
    vec2 g =(grad( p,b ));
    return normalize(v*g);
}

mat3 rot(in vec3 axe, in float angle)
{ 
    float s = sin(angle);
    float c = cos(angle);
    float d = 1.0 - c;
    axe = normalize(axe);
    float x=axe.x;
    float y=axe.y;
    float z=axe.z; 
    return  mat3(
   	d * x * x + c      , d * x * y - z * s ,  d * z * x + y * s,
               d * x * y + z * s,  d * y * y + c     ,  d * y * z - x * s,
               d * z * x - y * s ,  d * y * z + x * s,  d * z * z + c      );         
}                                                                              
vec3 rotate(vec3 v,vec3 axe,float a){
mat3 m=rot(axe,a);
return m*v;
}
void main( void ) {
	vec2 position = 2.0*( gl_FragCoord.xy / resolution.xy ) -1.0;
	position.y*=resolution.y/resolution.x;
	vec3 p=vec3(position,-2.0*mouse.y+2.*mouse.x);
	vec3 cc=vec3(sin(time*0.01),cos(time*0.2),sin(time*0.01));
	 p=(rotate(p,cc,time*0.02));
	p=4.*p*p*cc+p;
	vec2 colr=color(p.xy,length(p));
	gl_FragColor = vec4(1.-colr.x,colr.y,(colr.x+colr.y), 1.0 );
}