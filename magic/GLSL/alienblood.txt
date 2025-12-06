#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float hash(float x)
{
	return fract(sin(x) * 43758.5453);
}

float noise(vec3 x)
{
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	float n = p.x + p.y * 57.0 + p.z*113.0;
	
	float a = hash(n);
	return a;
}

float manhattan(vec3 v)
{
	v = abs(v);
	return v.x + v.y + v.z;
}

float cheby(vec3 v)
{
	v = abs(v);
	return v.x > v.y
	? (v.x > v.z ? v.x : v.z)
	: (v.y > v.z ? v.y : v.z);
}

float someMetric(vec3 v)
{
	return  pow(v.x,2.0) + pow(v.y,2.0) + pow(v.z,2.0);
}

float vor(vec3 v)
{
	vec3 start = floor(v);
	
	float dist = 1.0;
	vec3 cand;
	
	for(int z = -2; z <= 2; z += 1)
	{
		for(int y = -2; y <= 2; y += 1)
		{
			for(int x = -2; x <= 2; x += 1)
			{
				vec3 t = start + vec3(x, y, z);
				vec3 p = t + noise(t);
			
				float d = someMetric(p - v);

				if(d < dist)
				{
					dist = d;
					cand = p;
				}
			}
		}
	}
	
	vec3 delta = cand - v;
	
	return someMetric(delta);
}

void main( void )
{	
	vec2 p = ( gl_FragCoord.xy / resolution.xy );
	
	vec3 freq = vec3(0.0034, 0.0065, 0.75);
	vec3 v = vec3(5. * gl_FragCoord.xy, time) * freq;
	
	float w =  max(0., min(1., vor(v)));
	float w0 = smoothstep(.9, .1, w);
	float w1 = smoothstep(.2, .9, vor(w+v-w0));
	
	
	gl_FragColor = vec4(w + w0*w1) * vec4(p.x * .35, p.y + .8, .98, 7.);
}
