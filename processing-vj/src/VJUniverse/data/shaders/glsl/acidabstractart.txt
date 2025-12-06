#ifdef GL_ES
precision mediump float;
#endif
#define pi 1.141592653589793238462643383279

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// By uitham!
float tscale = 0.5;

float wave(vec2 position, float freq, float height, float speed) {
	float result = sin(position.x*freq - time*tscale*speed);
	result = result * 2.0 - 1.0;
	result *= height;
	return result;
}
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


vec4 main4( void ) {
	vec2 p = ( gl_FragCoord.xy / resolution.xy );
	p = (p * 2.0 - 1.0) * vec2(800, 600);
	p += mouse * 8196.0;
	float z = 84.0;
	float speed = 10.0;
	
	float v = snoise(p * 0.0075 + z + 0.05 * time * speed);  p += 1017.0;
	v +=  snoise(p * 0.0125 + z + 0.05 * time * speed) * 0.5;
	v +=  snoise(p * 0.02 + z + 0.05 * time * speed) * 0.35;
	v +=  snoise(p * 0.025 + z + 0.05 * time * speed) * 0.3125;
	v +=  snoise(p * 0.05 + z + 0.05 * time * speed) * 0.3;
	v +=  snoise(p  + z + 0.05 * time * speed) * 0.25;
	v = 0.1 * v + 0.5;
	
	return vec4(v*1.,sin(time)*0.5 + v,cos(time)*0.5 + v,sin(time)*0.5 + v);

}

vec3 combo(vec2 position, float center, float size) {
	
	float offset = pi * (center - 0.4);
	float lum   = abs(tan(position.y * pi + offset)) - pi/5.0;
	lum *= size;
	
        float red   = wave(position, 5.0, 0.9*size, 1.08);
	float green = wave(position, 3.5, 0.5*size, 1.23);
	float blue  = wave(position, 1.5, 1.2*size, 1.42);
	
	return vec3( lum + red, lum + green, lum + blue );
}
    	vec4 main3( void ) {

        vec2 position = - 10.0 * gl_FragCoord.xy / resolution.xy;
        float green = abs( tan( position.x * position.x + time / 1.0 ) );
        float blue = abs( sin( position.y * position.x + time / 1.0 ) );
        float red = abs( sin( position.y * position.y + time / 1.0 ) );
	return vec4( red, green, blue, 1.0 );

    	}

vec4 main2( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) + mouse / 4.0;

	float color = 0.0;
	color += sin( position.x * cos( time / 15.0 ) * 80.0 ) + cos( position.y * cos( time / 15.0 ) * 10.0 );
	color += sin( position.y * sin( time / 10.0 ) * 40.0 ) + cos( position.x * sin( time / 25.0 ) * 40.0 );
	color += sin( position.x * sin( time / 5.0 ) * 10.0 ) + sin( position.y * sin( time / 35.0 ) * 80.0 );
	color *= sin( time / 10.0 ) * 0.5;

	return vec4( vec3( color, color * 0.5, sin( color + time / 3.0 ) * 0.75 ), 1.0 );

}
void main( void ) {
	// normalize position
	vec2 position = gl_FragCoord.xy / resolution.xy;
	
	vec3 result = vec3(0.0, 0.0, 0.0);
	result += combo(position, 0.1+0.05*sin(0.6*time + 4.0*position.x), 0.05);
	result += combo(position, 0.5+0.05*sin(0.7*time + 3.0*position.x), 0.25);
	result += combo(position, 0.85+0.05*sin(0.42*time + 1.3*position.x), 0.05);

	gl_FragColor = vec4((vec4(result, 1.0) + sin(main2()+ time) + cos(main3()+ time) + tan(main4()+ time)) /sin(snoise(result.xy) + time));

}


