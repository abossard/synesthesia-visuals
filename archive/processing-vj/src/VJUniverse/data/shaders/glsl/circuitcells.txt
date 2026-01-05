#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// Cellular noise ("Worley noise") in 2D in GLSL.
// Copyright (c) Stefan Gustavson 2011-04-19. All rights reserved.
// This code is released under the conditions of the MIT license.
// See LICENSE file for details, located in ZIP file here:
// http://webstaff.itn.liu.se/~stegu/GLSL-cellular/

// Permutation polynomial: (34x^2 + x) mod 289
vec3 permute(vec3 x) {
  return mod((34.0 * x + 1.0) * x, 289.0);
}

// Cellular noise, returning F1 and F2 in a vec2.
// Standard 3x3 search window for good F1 and F2 values
vec2 cellular(vec2 P) {
#define K 0.142857142857 // 1/7
#define Ko 0.428571428571 // 3/7
#define jitter 0.58 // Less gives more regular pattern
	vec2 Pi = mod(floor(P), 289.0);
 	vec2 Pf = fract(P);
	vec3 oi = vec3(-1.0, 0.0, 1.0);
	vec3 of = vec3(-0.5, 0.5, 1.5);
	vec3 px = permute(Pi.x + oi);
	vec3 p = permute(px.x + Pi.y + oi); // p11, p12, p13
	vec3 ox = fract(p*K) - Ko;
	vec3 oy = mod(floor(p*K),7.0)*K - Ko;
	vec3 dx = Pf.x + 0.5 + jitter*ox;
	vec3 dy = Pf.y - of + jitter*oy;
	vec3 d1 = abs(dx) + abs(dy); // d11, d12 and d13, not squared
	p = permute(px.y + Pi.y + oi); // p21, p22, p23
	ox = fract(p*K) - Ko;
	oy = mod(floor(p*K),7.0)*K - Ko;
	dx = Pf.x - 0.5 + jitter*ox;
	dy = Pf.y - of + jitter*oy;
	vec3 d2 = abs(dx) + abs(dy); // d21, d22 and d23, not squared
	p = permute(px.z + Pi.y + oi); // p31, p32, p33
	ox = fract(p*K) - Ko;
	oy = mod(floor(p*K),7.0)*K - Ko;
	dx = Pf.x - 1.5 + jitter*ox;
	dy = Pf.y - of + jitter*oy;
	vec3 d3 = abs(dx) + abs(dy); // d31, d32 and d33, not squared
	// Sort out the two smallest distances (F1, F2)
	vec3 d1a = min(d1, d2);
	d2 = max(d1, d2); // Swap to keep candidates for F2
	d2 = min(d2, d3); // neither F1 nor F2 are now in d3
	d1 = min(d1a, d2); // F1 is now in d1
	d2 = max(d1a, d2); // Swap to keep candidates for F2
	d1.xy = (d1.x < d1.y) ? d1.xy : d1.yx; // Swap if smaller
	d1.xz = (d1.x < d1.z) ? d1.xz : d1.zx; // F1 is in d1.x
	d1.yz = min(d1.yz, d2.yz); // F2 is now not in d2.yz
	d1.y = min(d1.y, d1.z); // nor in  d1.z
	d1.y = min(d1.y, d2.x); // F2 is in d1.y, we're done.
	return (d1.xy);
}

void main( void ) {

	vec2 position = (( gl_FragCoord.xy / resolution.x ) - mouse * 2.0) * 16.0;

	vec2 F = cellular(position);
	float facets = 0.1+(F.y-F.x);
	float dots = smoothstep(0.05, 0.1, F.x);
  	float lines1 = 1.0 - smoothstep(0.1, 0.2, facets);
  	float lines2 = 1.0 - smoothstep(0.2, 0.3, facets);
  	float lines3 = 1.0 - smoothstep(0.3, 0.4, facets);
  	float lines4 = 1.0 - smoothstep(0.4, 0.5, facets);
  	float lines5 = 1.0 - smoothstep(0.5, 0.6, facets);
  	float lines6 = 1.0 - smoothstep(0.6, 0.7, facets);
  	float lines7 = 1.0 - smoothstep(0.7, 0.8, facets);
  	float lines8 = 1.0 - smoothstep(0.8, 0.9, facets);
  	float lines9 = 1.0 - smoothstep(0.9, 0.99, facets);
	float n = facets * dots;
	gl_FragColor = vec4(1.0 - dots,
                            max(1.0 - dots, facets * (lines1 - lines2 + lines3 - lines4 + lines5 - lines6 + lines7 - lines8 + lines9)),
                            n, 1.0);

}
