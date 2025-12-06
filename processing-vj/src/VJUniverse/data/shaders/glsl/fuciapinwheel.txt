#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
//float time = 0.0;
uniform vec2 mouse;
uniform vec2 resolution;
vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec2 mod289(vec2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec3 permute(vec3 x) {
  return mod289(((x*34.0)+1.0)*x);
}

float snoise(vec2 v)
{
  const vec4 C = vec4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                      0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                     -0.577350269189626,  // -1.0 + 2.0 * C.x
                      0.024390243902439); // 1.0 / 41.0
// First corner
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);

// Other corners
  vec2 i1;
  //i1.x = step( x0.y, x0.x ); // x0.x > x0.y ? 1.0 : 0.0
  //i1.y = 1.0 - i1.x;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  // x0 = x0 - 0.0 + 0.0 * C.xx ;
  // x1 = x0 - i1 + 1.0 * C.xx ;
  // x2 = x0 - 1.0 + 2.0 * C.xx ;
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;

// Permutations
  i = mod289(i); // Avoid truncation effects in permutation
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
		+ i.x + vec3(0.0, i1.x, 1.0 ));

  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;

// Gradients: 41 points uniformly over a line, mapped onto a diamond.
// The ring size 17*17 = 289 is close to a multiple of 41 (41*7 = 287)

  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;

// Normalise gradients implicitly by scaling m
// Approximation of: m *= inversesqrt( a0*a0 + h*h );
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );

// Compute final noise value at P
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}


vec4 perlin( void ) {
	vec2 p = ( gl_FragCoord.xy / resolution.xy );
	p = (p * 2.0 - 1.0) * vec2(800, 600);
	//p += mouse * 8196.0;
	p.y -= time * 596.0;
	float z = 84.0;
	float speed = 10.0;
	
	float v = snoise(p / 128. + z + 0.05 * time * speed);  p += 1017.0;
	v +=  snoise(p / 64. + z + 0.05 * time * speed) /2.;
	v +=  snoise(p / 32. + z + 0.05 * time * speed) /4.;
	v +=  snoise(p / 16. + z + 0.05 * time * speed) /8.;
	v +=  snoise(p / 8. + z + 0.05 * time * speed) /16.;
	v +=  snoise(p / 4.+ z + 0.05 * time * speed) /32.;
	v +=  snoise(p / 2.+ z + 0.05 * time * speed) /64.;
	v +=  snoise(p + z + 0.05 * time * speed) /128.;
	v = 0.1 * v + 0.5;
	
	return vec4(v*1.,0.5 + v,0.5 + v,0.5 + v);

}
void main()
{
	vec2 position = (gl_FragCoord.xy-resolution.xy/2.0) / resolution.yy + vec2(sin(time) / 6.0, cos(time) / 3.0);
	
	vec2 p = position * 800.;
	float len = sqrt(p.x*p.x+p.y*p.y*2.0);

	float ang = 2.0*atan(p.y,(len+p.x));
	ang += pow(len, 0.5)*1.0;
	
	float f = ang + -time*3.141592*2.0;
	float r = 6.0 - sin(f);
	float g = 2.0 - cos(f);
	float b = 2.0 + sin(f);
	vec3 color = vec3(r, g, b);

	color /= 2.;

	float ds = len/2000. * perlin().y;
	ds *= 10.;
	color *= (1.0-ds);
	
	//color = 1.-sqrt(1.2-color); // while coding
	color -= vec3(0.5);
	color *= vec3(1.5);
	color += vec3(0.5);
	
	gl_FragColor = vec4( color, 1.0 );

}