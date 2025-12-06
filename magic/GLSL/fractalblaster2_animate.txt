#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

/* -- originally --
 * inspired by http://www.fractalforums.com/new-theories-and-research/very-simple-formula-for-fractal-patterns/
 * a slight(?) different 
 * public domain
 */

// this version keeps the circle inversion at r=1,
// but the affine transform is variable:
// user controls the rotate and zoom,
// translate automatically cycles through a range of values.

#define N 100
#define PI2 6.2831853070

void main( void ) {
	// map frag coord and mouse to model coord
	vec2 v = (gl_FragCoord.xy - resolution / 2.) * 20.0 / min(resolution.y,resolution.x);
	// transform parameters
	float angle = PI2*mouse.x;
	float C = cos(angle);
	float S = sin(angle);
	vec2 shift = vec2( 0.0, 2.0+2.*sin(0.03*time) );
	float zoom = 2. + 5.*mouse.y;
	float rad2 = 1.;
	
	float rsum = 0.0;
	for ( int i = 0; i < N; i++ ){
		// circle inversion transform
		float rr = v.x*v.x + v.y*v.y;
		if ( rr > rad2 ){
			rr = rad2/rr;
			v.x = v.x * rr;
			v.y = v.y * rr;
		}
		rsum = max(rsum, rr);

		
		// affine transform: rotate, scale, and translate
		v = vec2( C*v.x-S*v.y, S*v.x+C*v.y ) * zoom + shift;
	}
	
	float col = rsum*rsum * (500.0 / float(N) / rad2);


	gl_FragColor = vec4( cos(col*1.8), cos(col*1.9), cos(col*2.2), 1.0 );

}