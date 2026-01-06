#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 mousePos;
	vec2 center0;
	vec2 center1;
	
	vec2  center00;
	vec2  center01;
	float r0;
	float r00;
	
	mousePos = mouse.xy*resolution.xy;

	r0 = resolution.x*0.075;
	r00 = r0 * 0.35;
	center0 = vec2(resolution.x*0.42, resolution.y*0.5);
	center00 = (mousePos - center0)*0.5 +center0;

	center1 = vec2(resolution.x*0.58, resolution.y*0.5);
	center01 = (mousePos - center1)*0.5 +center1;
	
	vec2 tmp;
	tmp = (center00 - center0);
	if (length(tmp) > (r0-r00)) {
		center00 = center0 + normalize(tmp)*(r0-r00);
	}
	
	tmp = (center01 - center1);
	if (length(tmp) > (r0-r00)) {
		center01 = center1 + normalize(tmp)*(r0-r00);
	}
	if (length( center00 - gl_FragCoord.xy) < r00) {
		gl_FragColor = vec4(0.0,0.0,0.0,1.0);
	} else if (length( center01 - gl_FragCoord.xy) < r00) {
		gl_FragColor = vec4(0.0,0.0,0.0,1.0);
	} else if (length( center0 - gl_FragCoord.xy) < r0 ) {
		gl_FragColor = vec4(1.0,1.0,1.0,1.0);
	} else if (length( center1 - gl_FragCoord.xy) < r0 ) {
		gl_FragColor = vec4(1.0,1.0,1.0,1.0);
	} else {
		gl_FragColor = vec4(0.0,0.0,0.0,1.0);
	}	
}