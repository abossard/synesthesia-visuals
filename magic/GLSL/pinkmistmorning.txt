// rotwang @mod+ spiral function, @mod* effect with 2 rotating spirals
// Trisomie21 try to mimic with a simpler 2d noise function

#ifdef GL_ES
precision mediump float;
#endif
uniform float time;
uniform vec2 resolution;


float hash(float n) { return fract(pow(sin(n), 1.1)*1e6); }

float snoise(vec2 p) {
	p *= 2.5;
	const vec2 d = vec2(1.,30.);
	vec2 f = fract(p), p0 = floor(p)*d, p1 = p0 + d;
	f.xy = f.xy * f.xy * (3.0 - 2.0 * f.xy);
	float t = mix(mix(hash(p0.x+p0.y), hash(p1.x+p0.y),f.x),
		       mix(hash(p0.x+p1.y), hash(p1.x+p1.y),f.x), f.y);
	return t*2.-1.;
}

float fbm( vec2 p) {
	float f = 0.0;
	f += 0.3000*snoise(p); p *= 3.22;
	f += 0.2500*snoise(p); p *= 3.03;
	f += 0.1250*snoise(p); p *= 3.01;
	f += 0.0625*snoise(p); p *= 3.04;
	return (f / 0.9375);
}

vec3 sun( vec2 pos ) {
	vec2 p = vec2(0.75, 0.9);
	return vec3(2.5, 0.5, 0.0) / (distance( p, pos ) * 25.0);
}

void main(void) {
	vec2 p = gl_FragCoord.xy / resolution.xy * 2.0 - 1.0;
	p.x /= resolution.y / resolution.x;
	vec3 c1 = mix(vec3(-0.9), vec3(0.1, 0.1, 1), gl_FragCoord.y/resolution.y);
	float c2 = fbm(p - time/20.) + fbm(p - time/25.) + fbm(p - time/50.) + 11.0;
	float v = (((c2 * 0.1) - .5) * .5) + 0.4;
	vec4 col = vec4( mix( c1, vec3(v), v ), 1.0 );
	gl_FragColor = vec4( col.rgb + sun( gl_FragCoord.xy / resolution.xy ), 1.0);
}