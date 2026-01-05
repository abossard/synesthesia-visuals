#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

#define N 12

void main( void ) {
	vec2 v = (gl_FragCoord.xy - resolution/2.0) / min(resolution.y,resolution.x) * 20.0;
	
	float x = v.x;
	float y = v.y;
	
	float t = time * 0.4;
	float r;
	for ( int i = 0; i < N; i++ ){
		float d = 3.14159265 / float(N) * float(i) * 5.0;
		r = length(vec2(x,y)) + 0.01;
		float xx = x;
		x = x + cos(y +cos(r) + d) + cos(t);
		y = y - sin(xx+cos(r) + d) + sin(t);
	}

	gl_FragColor = vec4( cos(r*sin(time*5.0)), cos(r*cos(time*10.0)), cos(r*sin(time*15.0)), 1.0 );

}