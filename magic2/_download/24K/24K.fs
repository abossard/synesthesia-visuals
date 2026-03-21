/*{
  "CREDIT": "",
  "CATEGORIES": [
    "plasma",
    "gold"
  ],
  "DESCRIPTION": "24k luxxxury plasma field",
  "INPUTS": []
}*/


// Original: https://www.shadertoy.com/view/MtBGDW

#define FIELD 20.
#define ITERATION 30.

#define t TIME
#define R RENDERSIZE
#define TONE vec3(0.299,0.587,0.114)

float face(vec3 p, float t) {
	vec2 fx = p.xy;
	p = abs ( p  );
	vec2 ab = vec2( 0.5 - p.x);
	for(float i=0.0; i < ITERATION; i++) {
		ab -= 0.5 * p.xy + cos(t * 0.1) * sin ( length(p*0.1) );
		
		p.y += sin( ab.x - p.z );
		p.x -= cos( ab.x ) * sin( t * 0.2);
		
		p -= (  p.x + p.x ) - t;
		p -= ( 2. * fx.y + cos(fx.x) );
		
        ab += vec2( p.y / t );
	}
	p /= FIELD;
	return p.x + p.y + p.x;
}


vec3 computeColor(float fx) {
	vec3 color = vec3(TONE);
	color -= (fx);
	color.r += color.g*2.0;
	color.g += color.b;
	return clamp(color, 0., 1.);
}

void main() {
	vec2 position = ( gl_FragCoord.xy - .5 * R ) / R.y;
	vec3 p = position.xyx*FIELD;
	
	vec3 color = computeColor( face(p, t) );
	gl_FragColor = vec4( color, 1.0 );
}