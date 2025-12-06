#ifdef GL_ES
precision mediump float;
#endif
// dashxdr was here 20120228
 
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
 
	vec2 position = ( 2.0*gl_FragCoord.xy - resolution) / resolution.xx;
 
	float adjust1 = mouse.x * 100.0;
	float adjust2 = mouse.y;
adjust1 = 50.0;
adjust2 = 1.0;

	position *= adjust1;
	float r = length(position);
	float fix = -time*1.3;
#define PI 3.1415927
#define PI2 (PI*2.0)

	float a = atan(position.y, position.x) + PI;
	float d = r - a + PI2;
	int n = int(d/PI2);
	d = d - float(n)*PI2;
	float dd = (d < PI*2.9) ? 1.0 : 0.0;
	float da = a+float(n)*PI2;
	vec3 norm;
	float pos = da*da*.07+fix;
#define IBALLRAD (1.0/.5)
	norm.xy = vec2(fract(pos) - .5, d / PI2 - .5)*IBALLRAD;
	float len = length(norm.xy);
	vec3 color = vec3(0.0, 0.0, 0.0);
	if(len <= 1.0)
	{
		norm.z = sqrt(1.0 -  len*len);
		vec3 lightdir = normalize(vec3(-0.0, -1.0, 1.0));
		dd = dot(lightdir, norm);
		dd = max(dd, 0.1);
		float rand = sin(floor(pos));
		color.rgb = dd*fract(rand*vec3(10.0, 1000.0, 100000.0));
		vec3 halfv = normalize(lightdir + vec3(0.0, 0.0, 1.0));
		float spec = dot(halfv, norm);
		spec = max(spec, 0.0);
		spec = pow(spec, 40.0);
		color += spec*vec3(3.0, 1.0, 1.0);
	}
	gl_FragColor.rgba = vec4(color, 1.0);
 
}