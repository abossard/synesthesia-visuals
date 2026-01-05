#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


#define NUM_MB 5

void main( void ) {
	vec2 mb[NUM_MB];
	float t = time/2.0;

	mb[0].xy = vec2(187,293);
	mb[1].xy = vec2(250,61);
	mb[2].xy = vec2(418,390);
	mb[3].xy = vec2(494,170);
	mb[4].xy = vec2(414,270);


	for(int i = 0; i < NUM_MB; i++)
		mb[i] = vec2(mb[i].x+sin(t*float(i))*100.0,mb[i].y+cos(t*float(i))*100.0);

	float e = 0.0;
	for(int i = 0; i < NUM_MB; i++)
		e += 1000.0/distance(gl_FragCoord.xy, mb[i]);

	gl_FragColor = vec4(sin(e/80.0), e/50.0,cos(time),0);
}