/*{
  "CREDIT": "by You",
  "DESCRIPTION": "",
  "CATEGORIES": ["Tunnel"],
  "INPUTS": [
    {
      "NAME": "c0",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": 0,
      "MAX": 8
    },
    {
      "NAME": "c1",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": 0,
      "MAX": 8
    },
    {
      "NAME": "c2",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": 0,
      "MAX": 8
    }
  ]
}*/

vec3   iResolution = vec3(RENDERSIZE, 1.0);
float  iGlobalTime = TIME;

const int MAX_ITER = 15; // 

vec2 rotate(in vec2 v, in float a) {
	return vec2(cos(a)*v.x + sin(a)*v.y, -sin(a)*v.x + cos(a)*v.y);
}

float torus(in vec3 p, in vec2 t)
{
	vec2 q = abs(vec2(max(abs(p.x), abs(p.z))-t.x, p.y));
	return max(q.x, q.y)-t.y;
}


float eval(in float x, in vec3 p) {
	if ( x < 1.0)
		return abs(max(abs(p.z)-0.5, abs(p.x)-0.1))-0.01;
	if ( x < 2.0)
		return length(max(abs(p.xy) - 0.5/10.,0.0));
	if ( x < 3.0)
		return length(p);
	if ( x < 4.0)
		return length(max(abs(p) - 0.35, 0.0));
	if ( x < 5.0)
		return abs(length(p.xz)-0.2)-0.01;
	if ( x < 6.0)
		return abs(min(torus(vec3(p.x, mod(p.y,0.4)-0.2, p.z), vec2(0.1, 0.05)), max(abs(p.z)-0.05, abs(p.x)-0.05)))-0.005;
	if ( x < 7.0)
		return abs(min(torus(p, vec2(0.3, 0.05)), max(abs(p.z)-0.05, abs(p.x)-0.05)))-0.005;
	if ( x < 8.0)
	return min(length(p.xz), min(length(p.yz), length(p.xy))) - 0.05;
}

// These are all equally interesting, but I could only pick one :(
float trap(in vec3 p)
{
	float a = eval(c0, p);
	float b = eval(c1, p);
	float c = eval(c2, p);
	
	return  min(max(a, -b), c);
//	return  min(max(a, b), c);
	
}

float map(in vec3 p)
{
	float cutout = dot(abs(p.yz),vec2(0.5))-0.035;

	vec3 z = abs(1.0-mod(p,2.0));
	float d = 999.0;
	float s = 1.0;
	for (float i = 0.0; i <4.0; i++) {
	    z.zx = rotate(z.zx, radians(i*10.0+iGlobalTime));
		z.zy = rotate(z.yz, radians((i+1.0)*20.0+iGlobalTime*1.1234));
		z = abs(1.0-mod(z+i/3.0,2.0));
		
		z = z*2.0 - 0.3;
		s *= 0.5;
		d = min(d, trap(z) * s);
	}
	return max(d, -cutout);
}

vec3 hsv(in float h, in float s, in float v) {
	return mix(vec3(1.0), clamp((abs(fract(h + vec3(3, 2, 1) / 3.0) * 6.0 - 3.0) - 1.0), 0.0 , 1.0), s) * v;
}

vec3 intersect(in vec3 rayOrigin, in vec3 rayDir)
{
	float total_dist = 0.0;
	vec3 p = rayOrigin;
	float d = 1.0;
	float iter = 0.0;
	float mind = 3.14159;
	
	for (int i = 0; i < MAX_ITER; i++)
	{		
		if (d < 0.001) continue;
		
		d = map(p);
		p += d * rayDir;
		mind = min(mind, d);
		total_dist += d;
		iter++;
	}

	vec3 color = vec3(0.0);
	float x = (iter/float(MAX_ITER));

	float q = 1. - x;
	color = vec3(1.0) * q;
	return color;
}

void main()
{
	vec3 upDirection = vec3(0, -1, 0);
	vec3 cameraDir = vec3(1,0,0);
	vec3 cameraOrigin = vec3(iGlobalTime*0.1, 0, 0);

	
	vec2 screenPos = -1.0 + 2.0 * gl_FragCoord.xy / iResolution.xy;
	screenPos.x *= iResolution.x / iResolution.y;
	vec3 rayDir = normalize(vec3(1.0, screenPos));
	
	gl_FragColor = vec4(intersect(cameraOrigin, rayDir), 1.0);
} 