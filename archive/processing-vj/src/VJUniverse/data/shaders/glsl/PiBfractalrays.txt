#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float loopto(float a, float top) {
	a = mod(a, top*2.0);
	if(a < top)
		return a;
	else
		return top*2.0-a;
}

void main( void ) {
	float time = time / 10. ;
	float a = time, cosa = cos(a), sina = sin(a);
	vec2 position = gl_FragCoord.xy / resolution.xy * 2.0 - 1.  ;
	position = vec2(position.x * cosa - position.y * sina, position.y*cosa + position.x * sina) + 0.3 * cos(time * 10.);
	position = (sin(vec2(length(position), cos(atan(position.y / position.x)))));

	position *= ((acos(position) / (position * (time / 5.) * loopto(time, 5.)))) / 5. * sin((position * 5.) * (time/50.));
	
	time = (time * 5.) * 2.;
	gl_FragColor = vec4(abs(sin(1. * time)), 0.1 , abs(cos(-0.1* time)), 1.) * cos(position.y*3000. + time / 5. + position.x * time );
}