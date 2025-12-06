#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
uniform sampler2D backbuffer;

#define N 3

void main( void ) 
{
	vec2 v = (gl_FragCoord.xy - resolution/2.0) / min(resolution.y,resolution.x) * 20.0;
	
	float t = time*.3;

	float repeat = mouse.y * 10.0;
	float factor = mouse.x * 10.0;
	float r;
	
	for ( int i = 0; i < N; i++ ){
//		float d = 3.14159265 / float(N) * 5.0;
		if ( float(i) < repeat ){
			v += vec2(
			  cos(v.y + cos((v.x+t)*factor)  - t) ,
			  sin(v.x + sin((v.y+t)*factor)  - t)  
			);		
		}
	}
	r = length(v);
	gl_FragColor = vec4( cos(r*0.5), cos(r*1.0), cos(r*2.0), 1.0 ) /* *.1+texture2D(backbuffer,gl_FragCoord.xy/resolution)*.9*/;

}