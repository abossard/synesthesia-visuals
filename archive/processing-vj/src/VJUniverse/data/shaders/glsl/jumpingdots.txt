#ifdef GL_ES
precision mediump float;
#endif

// dabobs

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


vec3 bob(vec2 p, vec2 t, float r, float i) {
	if (length(t-p) < r) {
		return vec3(i*0.3, i*0.2, p.x);
	}
	return vec3(0.0);
}

void main( void ) {

	vec2 p = gl_FragCoord.xy / resolution.xy;
	float a = resolution.x/resolution.y;
	p.x = p.x*a;
	vec2 m = vec2(mouse.x*a, mouse.y);
	vec3 col = vec3(0.0);
	for (float i=0.0; i < 4.5; i+=0.1) {
	  col += vec3(bob(p, vec2(1.0+0.9*cos(mouse.x*8.0*i+0.1*time+cos(i+time)), 0.5 + 0.45*sin(3.0*i+2.0*0.1+4.0*time+sin(i+time))), 0.1, i));
	}
	gl_FragColor = vec4(vec3(col), 1.0);
}