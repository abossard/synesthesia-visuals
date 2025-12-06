#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
#define PI 3.14159
#define TWO_PI (PI*2.0)
#define N 3.0

void main( void ) {

	vec2 position = ( gl_FragCoord.xy) * 1.0;// * resolution;

	float color = 0.0;
	//float N = mod(time/0.0, 10.0);
	for(float i = 0.0; i < N; i+=1.0) {
	  	float a = i * (TWO_PI/N) *(time)*0.1;
		color+= cos( ((position.x-resolution.x/2.0) * cos(a) + (position.y-resolution.y/2.0) * sin(a) + time*10.01) * 0.09);
	}
	
	
	

	color/= 0.010;
	//color = position.x *cos(time);
	gl_FragColor = vec4( vec3( color), 1.0 );

}