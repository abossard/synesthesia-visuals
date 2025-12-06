#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
// I couldn't resist playing around with Kali's "Cosmos" shader!
// Made here:- https://www.shadertoy.com/view/Msl3WH
// Adapted it from here:-   https://www.shadertoy.com/view/MssGD8

// I couldn't resist playing around with Kali's "Cosmos" shader!
// Adapted it from here:-   https://www.shadertoy.com/view/MssGD8

float time2 = (time+2.4) * 60.0;

void main(void)
{
	float s = 0.0, v = 0.0;
	vec2 uv = (gl_FragCoord.xy / resolution.xy) * 2.0 - 1.0;
	uv.x *= resolution.x/resolution.y;
	
	float t = time2*0.005;
	uv.x += sin(t)*.5;
	
	float si = sin(t+3.);
	float co = cos(t+1.);
	mat2 rot = mat2(co, si, -si, co);
	uv *= rot;
	vec3 col = vec3(0.0);
	
	for (int r = 0; r < 100; r++) 
	{
		vec3 p= vec3(0.3, 0.2, floor(time2) * 0.0008) + s * vec3(uv, 0.143);
		p.z = mod(p.z,2.0);
		for (int i=0; i < 10; i++)
		{
			p = abs(p*2.15) / dot(p,p) -.965;
		}
		v += length(p*p)*smoothstep(0.,.5, .9 - s) * .0004;
		// Vary colour between red, purple and cyan...
		col +=  vec3(s * .6, .9, v * 3.5)*v*0.009;
		s += .01;
	}
	gl_FragColor = vec4(col, 1.0);
}