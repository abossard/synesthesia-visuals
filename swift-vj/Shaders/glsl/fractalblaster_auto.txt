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
	float C = cos(mouse.x * pi2 / 2. + pi2 / 4.)*((tan(time)*0.1)+1.);
	float S = sin(mouse.x * pi2 / 2. + pi2 / 4.)*((tan(time)*0.1)+1.);
	vec2 shift = vec2( 0.0, 1.0 );
	float zoom = (mouse.y*1.0 + 1.0);
	
	for ( int i = 0; i < N; i++ ){
		float rr = v.x*v.x+v.y*v.y;
		if ( rr > 1.0 ){
			rr = 1.0/rr;
			v.x = v.x * rr;
			v.y = v.y * rr;
		}
		rsum *= 0.99;
		rsum += rr;
		
		v += 0.05*sin(atan(v.y+mouse.y, v.x+mouse.x)*2.0);
		v = vec2( C*v.x-S*v.y, S*v.x+C*v.y ) * zoom + shift;
	}
	
	float col = rsum;


	gl_FragColor = vec4( cos(col), sin(col*3.-3.14/2.), sin(col*2.-3.14/4.), 1.0 ) * 0.5 + 0.5;

}