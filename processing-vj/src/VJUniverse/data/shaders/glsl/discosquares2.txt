#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// Shabtronic - simple seizure plane deform - can be timed to some beats :)

void main( void ) 
{
float t=time*0.35;
vec2 p=-1.0+2.0*gl_FragCoord.xy/resolution;
p+=p.x*sin(p.x*p.y+t*0.1)-p.y*sin(p.x*p.y+t*0.5);
vec2 col=abs(floor((p)/0.125)+t*vec2(6.0,13.0));
p=mod(p,0.125)-0.0525;
float contrast=2.0+abs(cos(t))*20.0;
gl_FragColor=length(250.0*p*p-normalize(p)*0.2)*vec4(0.2,0.06,0.05,1);
gl_FragColor=(gl_FragColor*contrast)-vec4(mod(col.x*0.25,1.0),0.4*mod(col.y*0.333,1.0),0.1,1.0)*contrast*0.25;


}