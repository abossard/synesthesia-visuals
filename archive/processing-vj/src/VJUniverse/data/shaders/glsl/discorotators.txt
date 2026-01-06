#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

#define M_PI 3.141592653589793

// hexagon by @hintz 2013-05-07

void main(void)
{
	vec2 position = (gl_FragCoord.xy - 0.5 * resolution.xy) / resolution.x;
	
	float a = 0.1*time*M_PI/3.0;
	float c = cos(a);
	float s = sin(a);
	mat2 rotate = mat2(c,s,-s,c);
	vec2 q = tan(position*50.0);
	
	vec3 color = vec3(length(position+q));
	color.rg *= abs(0.2-position.x);
	vec2 p2 = position * rotate;
	color.gb *= abs(0.2-p2.x);

	vec2 p3 = p2 * rotate;
	color.br *= abs(0.2-p3.x);

	vec2 p4 = p3 * rotate;
	color.rg *= abs(0.2-p4.x);

	vec2 p5 = p4 * rotate;
	color.gb *= abs(0.2-p5.x);

	vec2 p6 = p5 * rotate;
	color.br *= abs(0.2-p6.x);
	
	color.g *= abs(position.x);
	color.b *= abs(p2.x);
	color.r *= abs(p3.x);
	
	gl_FragColor = vec4(1.0-100000.0*color, 1.0);
}