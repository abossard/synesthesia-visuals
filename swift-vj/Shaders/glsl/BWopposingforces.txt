#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
const float a = 1.;
uniform vec2 mouse;
uniform vec2 resolution;

vec3 getColor (vec2 v) {
	return vec3(1. - mod(v.x / 16., 2.));
	if (floor(mod(v.x / 16., 2.)) == 0.) return vec3(1.);
	return vec3(0.);
}

void main( void ) {

	float fac = (floor(mod(gl_FragCoord.x / 16., 2.)) == 0.) ? 1. : -1.;
	vec3 color = getColor(gl_FragCoord.xy + vec2(sin(gl_FragCoord.y * 0.25 + time + time * 10. * fac) * 15., 0.));
	
	gl_FragColor = vec4(color, 1.);

}