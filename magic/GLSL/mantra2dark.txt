#ifdef GL_ES
precision mediump float;
#endif
// dashxdr was here 20120228
 
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
 
	vec2 position = ( 1.0*gl_FragCoord.xy - resolution/2.0) / resolution.xx;
 
	float adjust1 = mouse.x * 100.0;
	float adjust2 = mouse.y;
adjust1 = 50.0;
adjust2 = 1.0;

	position *= adjust1;
	float r = length(position);
	float fix = time;
#define PI 3.1415927
#define PI2 (PI*2.0)

	float a = atan(sin(position.y/5.0), cos(position.y/3.0)) + PI;
	float q = cos(position.x);
	float p = sin(position.y);
	float d = r - a + PI2;
	int n = int(d/PI2);
	d = d - float(n)*PI2;
	float dd = 1.0;
	a=a+q/d+p/d;
	float da = a+float(n)*PI2;
	vec3 norm;
	float pos = da*da*.05+fix;
#define IBALLRAD (1.0/.5)
	norm.xy = vec2(fract(pos) - d/2.0, d / 6.0 - .2)*IBALLRAD;
	float len = length(norm.yx);
	vec3 color = vec3(0.0,0.0, 0.0);
	if(len <= 2.0)
	{
		norm.z = sqrt(1.0 -  len*len);
		vec3 lightdir = normalize(vec3(-3.0, 1.0, 8.0));
		dd = dot(lightdir, norm);
		dd = max(dd, 0.1);
		float rand = cos(floor(pos));
		color.rgb = dd*fract(rand*vec3(22210.0, 50.0, 100.0));
		vec3 halfv = normalize(lightdir + vec3(9.0, 2.0, 1.0));
		float spec = dot(halfv, norm);
		spec = max(spec, 0.970);
		spec = pow(spec, 70.0);
		color += spec*vec3(3.0, 1.0, 1.0);
	}
	gl_FragColor.rgba = vec4(color, 1.0);
 
}