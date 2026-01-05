#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 uPos = ( gl_FragCoord.xy / resolution.y/2.0 );//normalize wrt y axis
	vec2 rPos = uPos;
	
	uPos -= vec2((resolution.x/resolution.y)/4.0, 0.5) - 0.1*sin(tan(time / 2.0)+(gl_FragCoord.x / 50.0)*3.0);//shift origin to center
	rPos -= vec2((resolution.x/resolution.y)/4.0, 0.5) - 0.1*sin(tan(time / 3.2)+(gl_FragCoord.y / 100.0)*2.0);//shift origin to center
	
	float color = 0.0;
	
	float dist = length(uPos - vec2(0.05, -0.2));
	dist *= dist*exp(dist);
	
	float dist2 = length(rPos);
	vec2 val = vec2( 1.0/pow(dist*3.0+0.9, 10.0));
	vec2 val2 = vec2(pow(dist2,1.1));
	
	gl_FragColor = vec4( val.x + val2.y, val.y*val2.x, val2.x*val2.y, 1.0 );
}