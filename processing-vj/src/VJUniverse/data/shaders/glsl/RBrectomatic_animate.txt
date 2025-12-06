#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

/*
 * inspired by http://www.fractalforums.com/new-theories-and-research/very-simple-formula-for-fractal-patterns/
 * a slight(?) different 
 * public domain
 */

#define N 40
void main( void ) {
	vec2 v = (gl_FragCoord.xy - resolution/2.0) / min(resolution.y,resolution.x) * 20.0;

	float rsum = 0.0;
	float pi2 = 3.1415926535 * 2.0;
	float C = cos(mouse.x * pi2);
	float S = sin(mouse.x * pi2);
	vec2 shift = vec2( 0.0, 1.0 );
	vec2 c = mouse;
	
	for ( int i = 0; i < N; i++ ){
		c = vec2( C*c.x-S*c.y, S*c.x+C*c.y );
		v = abs(v)/(v.x*v.y) + c;
		rsum += length(v);
	}
	
	float col = log(rsum);


	gl_FragColor = vec4( cos(col*1.0), cos(col*2.0), cos(col*4.0), 1.0 );

}