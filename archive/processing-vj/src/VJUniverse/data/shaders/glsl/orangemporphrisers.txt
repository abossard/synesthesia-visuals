#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float textureRND2D(vec2 uv)
{
	vec2 f = fract(uv);
	f = f*f*(3.0-2.0*f);
	uv = floor(uv);
	float v = uv.x+uv.y*1e3;
	vec4 r = vec4(v, v+1., v+1e3, v+1e3+1.);
	r = fract(1e5*sin(r*1e-3));
	return mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y);	
}

void main( void )
{
	vec2 p = gl_FragCoord.xy/resolution.xy;
	float c = step(textureRND2D(p*5.+vec2(0.,-time)),p.y*.7+.1);
	gl_FragColor = vec4(mix(vec3(1.2,.5,0.2)*p.y, vec3(p.y), c),1.0);
}