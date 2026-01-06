// rotwang @mod+ spiral function, @mod* effect with 2 rotating spirals

#ifdef GL_ES
precision mediump float;
#endif
uniform float time;
//uniform vec2 mouse;
uniform vec2 resolution;

const float threshold = 20.0;
const float PI = 3.1415;
const float TWOPI = 2.0*PI;


vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }

// Perlin simplex noise
float snoise(vec2 v)
  {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
					 -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
//  i1.x = step( x0.y, x0.x ); // x0.x > x0.y ? 1.0 : 0.0
//  i1.y = 1.0 - i1.x;
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
	+ i.x + vec3(0.0, i1.x, 1.0 ));
  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy),
    dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

float fbm( vec2 p)
{
	float f=0.0;
	
	f += 0.5000*snoise(p); p*=2.02;
	f += 0.2500*snoise(p); p*=2.03;
	f += 0.1250*snoise(p); p*=2.01;
	f += 0.0625*snoise(p); p*=2.04;
	f /= 0.9375;
	return f;
}

float spiral(vec2 p, float rpm, float blades, float rings, float time)
{
	float t = time * rpm/60.0;
	p *= mat2(vec2(cos(t*TWOPI),sin(t*TWOPI)),vec2(-sin(t*TWOPI),cos(t*TWOPI)));
	vec2 c = vec2(0.0);
	float dist = distance(p, c)*TWOPI*rings*blades;
	dist = pow(dist,0.5)*5.0;
	float angle = atan(p.y,p.x)/PI/2.0;
	if (p.y<0.0) angle = atan(-p.y,-p.x)/PI/2.0+0.5;

	float brightness = ((cos((dist+angle*PI*4.0*blades)*0.5) + 2.0) /4.0);
	brightness += 1.0- length(p);

	return brightness;
}

void main(void)
{
	vec2 p = gl_FragCoord.xy/resolution.xy*2.0-1.0;
	p.x/=resolution.y/resolution.x;
	//
	
	vec3 c1 = vec3(
		spiral(p    ,3.,6.,1.,time),
		spiral(p+0.1,7.,5.,1.,time+0.2),
		spiral(p-0.1,21.,4.,1.,time+0.15) );
	
	vec3 c2 = vec3(
		fbm(p+1.5),
		fbm(p+1.2+time+time),
		fbm(p+1.1-time)
		);
	
	
	//	float sa = spiral(p, 2.0, 10.0, 4.0); 
	
	vec3 c = vec3(0.);

	c = mix(c1, c2, 0.1);
	
	gl_FragColor = vec4( c,1.0);//smoothstep(0.0, dist, brightness));
}