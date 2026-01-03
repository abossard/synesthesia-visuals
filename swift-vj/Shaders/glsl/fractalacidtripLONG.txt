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

// vectorize more and remove the annoying mouse plus some funky colors

#define N 32
#define PI2 6.2831853070

void main( void ) {
	// map frag coord and mouse to model coord
	vec2 v = (gl_FragCoord.xy - resolution / 2.) * 20.0 / min(resolution.y,resolution.x);
	vec2 ov = v;
	// transform parameters
	float t = time*0.01;
	float tsin = (1.0 -(sin(t)*0.5));
	float angle = PI2*tsin;
	float C = cos(angle);
	float S = sin(angle);
	vec2 shift = vec2( 0.0, 2.0+2.*sin(0.05*time) );
	float zoom = 2. + 5.*(tsin*0.5);
	float rad2 = 1.0;
	
	float rsum = 0.0;
	for ( int i = 0; i < N; i++ ){
		// circle inversion transform
		float rr = dot(v,v);
		if ( rr > rad2 ){
			rr = rad2/rr;
			v = v * rr;
		}
		rsum *= 0.99;
		rsum += rr;
		
		// affine transform: rotate, scale, and translate
		v = (vec2( C*v.x-S*v.y, S*2.0*v.x+C*v.y) * zoom) + shift;
	}
	
	float col = rsum * (50.0 / float(N) / rad2);


	gl_FragColor = vec4( fract(1.0+cos(col+1.0+time)), fract(1.0+cos(col*2.0+time)), fract(1.0+cos(col+3.0+time)), 1.0 );

}