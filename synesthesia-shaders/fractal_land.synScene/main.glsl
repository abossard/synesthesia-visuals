// ============================================================================
// FRACTAL LAND SHADER
// ============================================================================
// A raymarched fractal scene with animated camera, waves, and optional Nyan Cat

// Feature flags
#define NYAN 
#define WAVES
//#define BORDER
#define SHOWONLYEDGES

// Raymarching parameters
#define RAY_STEPS 180

// Color post-processing
#define BRIGHTNESS 1.2
#define GAMMA 1.4
#define SATURATION 0.65

// Distance estimation detail (adaptive detail increases with distance)
#define detail 0.0015

// Time variable (scaled for animation speed)
#define t advance

// Camera origin offset
const vec3 origin = vec3(-1.0, 0.7, 0.0);

// Global variable for adaptive detail (used in normal calculation)
float det = 0.001;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// 2D rotation matrix
mat2 rot(float angle) {
	return mat2(cos(angle), sin(angle), -sin(angle), cos(angle));	
}

// ============================================================================
// FRACTAL FORMULA
// ============================================================================

// "Amazing Surface" fractal formula (iterative transformation)
vec4 formula(vec4 p) {
    
    vec2 g1=geometry1, g2=geometry2;
	// Fold operation on xz plane
	p.xz = abs(p.xz + g1.x) - abs(p.xz - g1.x) - p.xz;
	
	// Translate and rotate
	p.y -= .2;
	p.x -= g2.x *.7;
	p.xy *= rot(radians(10.0+g1.y*25.0));

	// Spherical inversion
	p = p * (1.7+g2.y) / clamp(dot(p.xyz, p.xyz), 0.2, 1.);
	

	return p;
}

// ============================================================================
// DISTANCE ESTIMATION
// ============================================================================

// Distance estimation function (returns distance to nearest surface)
float de(vec3 pos) {
	// Optional wave animation on Y axis
	#ifdef WAVES
	    pos.y+=sin(pos.z-t*3.)*.5*waves;
	#endif

    pos.xy*=rot(sin(syn_BassTime*twist_audio+pos.z*.5+pos.x*.25+TIME*.5)*.25*twist);
	float x = pos.x+1.;
    if (tunnel==1.) pos.y=1.25-abs(pos.y-1.25);
	
	// Create tiling pattern along Z axis
	vec3 tpos = pos;
	tpos.x -= geometry1.x - 1.;
	tpos.z = abs(3.0 - mod(tpos.z, 6.0));
	// Iterate fractal formula
	vec4 p = vec4(tpos, 1.0);
	for (int i = 0; i < 4; i++) {
		p = formula(p);
	}
	
	// Fractal distance
	float fr = (length(max(vec2(0.0), p.yz - 1.5)) - 1.0) / p.w;
	
	// Additional geometric shapes (rocks/obstacles)
	float ro = max(abs(pos.x + 1.0) - 0.3, pos.y - 0.35);
	ro = max(ro, -max(abs(pos.x + 1.0) - 0.1, pos.y - 0.5));
	pos.z = abs(0.25 - mod(pos.z, 0.5));
	ro = max(ro, -max(abs(pos.z) - 0.2, pos.y - 0.3));
	ro = max(ro, -max(abs(pos.z) - 0.01, -pos.y + 0.32));
	
	// Return minimum distance (union operation)
	float d = min(fr, ro);
	d=max(d,abs(x)-5.);
	return d*.8;
}

// ============================================================================
// CAMERA PATH
// ============================================================================

// Camera path function (defines camera movement over time)
vec3 path(float ti) {
	ti *= 1.5;
	vec3 p = vec3(
		sin(ti)*cam_wave,
		(1.3 - sin(ti * 2.0)) * 0.5*cam_wave,
		-ti * 5.0
	) * 0.5;
	return p;
}

// ============================================================================
// NORMAL CALCULATION & EDGE DETECTION
// ============================================================================

// Global edge detection variable
float edge = 0.0;

// Calculate surface normal using finite differences
// Also performs edge detection for wireframe effect
vec3 normal(vec3 p) { 
	vec3 e = vec3(0.0, det * 5.0, 0.0);
	
	// Sample distance field in 6 directions
	float d1 = de(p - e.yxx);
	float d2 = de(p + e.yxx);
	float d3 = de(p - e.xyx);
	float d4 = de(p + e.xyx);
	float d5 = de(p - e.xxy);
	float d6 = de(p + e.xxy);
	float d = de(p);
	
	// Edge detection: compare center with average of neighbors
	edge = abs(d - 0.5 * (d2 + d1)) + 
	       abs(d - 0.5 * (d4 + d3)) + 
	       abs(d - 0.5 * (d6 + d5));
	edge = min(1.0, pow(edge, 0.55) * 15.0);
	
	// Calculate normal from gradient
	return normalize(vec3(d1 - d2, d3 - d4, d5 - d6));
}

// ============================================================================
// NYAN CAT EFFECTS (Based on mu6k's code)
// ============================================================================

// Render rainbow trail
vec4 rainbow(vec2 p) {
    if (tunnel == 1.) return vec4(0);
	float q = max(p.x, -0.1);
	float s = sin(p.x * 7.0 + (t+syn_HighTime*0.06) * 70.0) * 0.08;
	p.y += s;
	p.y *= 1.1;
	
	vec4 c;
	if (p.x > 0.0) {
		c = vec4(0, 0, 0, 0);
	} else if (0.0 / 6.0 < p.y && p.y < 1.0 / 6.0) {
		c = vec4(255, 43, 14, 255) / 255.0;
	} else if (1.0 / 6.0 < p.y && p.y < 2.0 / 6.0) {
		c = vec4(255, 168, 6, 255) / 255.0;
	} else if (2.0 / 6.0 < p.y && p.y < 3.0 / 6.0) {
		c = vec4(255, 244, 0, 255) / 255.0;
	} else if (3.0 / 6.0 < p.y && p.y < 4.0 / 6.0) {
		c = vec4(51, 234, 5, 255) / 255.0;
	} else if (4.0 / 6.0 < p.y && p.y < 5.0 / 6.0) {
		c = vec4(8, 163, 255, 255) / 255.0;
	} else if (5.0 / 6.0 < p.y && p.y < 6.0 / 6.0) {
		c = vec4(122, 85, 255, 255) / 255.0;
	} else if (abs(p.y) - 0.05 < 0.0001) {
		c = vec4(0.0, 0.0, 0.0, 1.0);
	} else if (abs(p.y - 1.0) - 0.05 < 0.0001) {
		c = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		c = vec4(0, 0, 0, 0);
	}
	
	// Fade alpha based on distance
	c.a *= 0.8 - min(0.8, abs(p.x * 0.08));
	c.xyz = mix(c.xyz, vec3(length(c.xyz)), 0.15);
	return c;
}

// Render Nyan Cat sprite
vec4 nyan(vec2 p) {
    if (tunnel == 1.) return vec4(0.);
	vec2 uv = p * 1.0;
	uv.y += 0.45;
	uv.x -= 0.2;
	
	float ns = 3.0;
	float nt = TIME * ns;
	nt -= mod(nt, 240.0 / 256.0 / 6.0);
	nt = mod(nt, 240.0 / 256.0) * 0.0;
	float ny = mod(TIME * ns, 1.0);
	ny -= mod(ny, 0.75);
	ny *= -0.05 * 0.0;
	
	vec2 uv2 = uv;
	uv2.x = 1.-uv2.x;
	vec4 color = _textureMedia(uv2);
	
	// Clamp UV bounds
	if (uv.x < -1.0) color.a = 0.0;
	if (uv.x > 0.0) color.a = 0.0;
	if (uv.y > 1.0) color.a = 0.0;
	if (uv.y < 0.0) color.a = 0.0;
	
	return color;
}

// ============================================================================
// RAYMARCHING
// ============================================================================

// Main raymarching function
vec3 raymarch(in vec3 from, in vec3 dir) {
	edge = 0.0;
	vec3 p, norm;
	float d = 100.0;
	float totdist = 0.0;
	
	// Raymarching loop
	for (int i = 0; i < RAY_STEPS; i++) {
			p = from + totdist * dir;
			d = de(p);
			det = detail * exp(0.13 * totdist); // Adaptive detail
			totdist += d;
		if (d < det || totdist > 25.0) {
		    break;
		}
	}
	
	vec3 col = vec3(0.0);
	
	// Refine intersection point
	p -= (det - d) * dir;
	norm = normal(p);
	
	// Surface coloring
	if (edges_mode == 1.) {
		col = 1.0-vec3(edge); // Wireframe mode
	}
	else {
		col = (1.0 - abs(norm)) * max(0.0, 1.0 - edge); // Normal-based color with dark edges
	}
	
	//col*=edge*8.;
	//col=vec3(edge*edge);
	
	col.rb *= rot(RB_rotation*1.5-totdist*Z_variation*0.5);
	col.rg *= rot(RG_rotation*1.5-totdist*Z_variation*0.5);
	col.gb *= rot(GB_rotation*1.5-totdist*Z_variation*0.5);
    col=abs(col);

	totdist = clamp(totdist, 0.0, 26.0);
	dir.y -= 0.02;
	
	// Sky and sun rendering
	float sunsize = 8.0 - mix(0.0, syn_BassLevel*0.5+syn_MidLevel*0.5, 0.3+0.7*syn_Presence)*3.;
	
	// Sun components
	vec2 sunDir = dir.xy+vec2(0.0,0.11-syn_Presence*0.13) * (tunnel == 1 ? 0 : 1);
    float l=length(sunDir.xy);
	float an = atan(sunDir.x, sunDir.y) + syn_Time *0.1* 1.5; // Rotating sun angle
	float s = pow(clamp(1.0 - l * sunsize - abs(0.2 - mod(an, 0.4)), 0.0, 1.0), 0.1); // Sun core
	float sb = pow(clamp(1.0 - l * (sunsize - 0.2) - abs(0.2 - mod(an, 0.4)), 0.0, 1.0), 0.1); // Sun border
	float sg = pow(clamp(1.0 - l * (sunsize - 4.5) - 0.5 * abs(0.2 - mod(an, 0.4)), 0.0, 1.0), 3.0); // Sun rays
	
	// Sky gradient
	float y = mix(0.45, 1.2, pow(smoothstep(0.0, 1.0, 0.75 - dir.y), 2.0)) * (1.0 - sb * 0.5);
	
	// Background composition
    vec3 backc = vec3(0.5, 0.0, 1.0);
    backc.rb *= rot(RB_rotation*1.5);
    backc.rg *= rot(RG_rotation*1.5);
    backc.gb *= rot(GB_rotation*1.5);
	backc=abs(backc);


	vec3 backg = backc * ((1.0 - s) * (1.0 - sg) * y + (1.0 - sb) * sg * vec3(1.0, 0.8, 0.15) * 3.0);
	backg += vec3(1.0, 0.9, 0.1) * s;
	backg = max(backg, sg * vec3(1.0, 0.9, 0.5));
	
	
	float nosound = step(syn_Level,.05);
	
	// Distance fog (fade to sun color)
	col = mix(vec3(1.0, 0.9, 0.3)*1.1, col*(.4+sunsize*.1+nosound*.1), (clamp(exp(-0.004 * totdist * totdist)-syn_BassLevel*mix(.2,0.3,edges_mode)-syn_BassLevel*.3*step(.1,tunnel)+abs(dir.x)*.5,0.,1.)));
	
	// Background replacement for distant objects
	float hit = 1.0;
	if (totdist > 25.0) {
		hit = 0.0;
		col = backg;
	}
	// Post-processing
	col = pow(col, vec3(GAMMA)) * BRIGHTNESS;
	col = mix(vec3(length(col)), col, SATURATION);
	
	if (edges_mode == 1.) {
		// col = vec3(length(1.0-col)*.7);
		float pulse1 = _nsin(norm.z*2.0+norm.y*2.0+TIME+syn_BassTime*0.2-p.z*0.1+p.y*0.1);
		float pulse2 = _nsin(p.z*0.05+(norm.y+norm.z+norm.x*0.1)*PI+TIME);
		//If we don't "hit" or are not the sun border, color us white
		//Change from white based on pulse1
		//Change color from red to magenta based on pulse2
		//Expand the range on edges_color, with special breakpoints when edges color is 0.5
		col =  vec3(1.0-length(col)*.75)*(mix(mix(vec3(1.0), vec3(3.0,pulse1*0.5,1.5*pulse1), min(hit+sb,min(edges_color*2.0,1.0))), vec3(1.0), 1.0-_pulse(pulse2, 0.5, 0.16+(edges_color-0.5)*2.0*0.74)));

	} else {
		col *= vec3(1.0, 0.9, 0.85);
		
		// Nyan Cat overlay
		#ifdef NYAN
			dir.yx *= rot(dir.x);
			vec2 ncatpos = (dir.xy + vec2(-3.0 + mod(-t, 6.0), -0.27));
			vec4 ncat = nyan(ncatpos * 5.0);
			vec4 rain = rainbow(ncatpos * 10.0 + vec2(0.8, 0.5));
			if (totdist > 8.0) col = mix(col, max(vec3(0.2), rain.xyz), rain.a * 0.9);
			if (totdist > 8.0) col = mix(col, max(vec3(0.2), ncat.xyz), ncat.a * 0.9);
		#endif
	}
	
	return col;
}

// ============================================================================
// CAMERA MOVEMENT
// ============================================================================

// Calculate camera position and orientation
vec3 move(inout vec3 dir) {
	vec3 go = path(t);
	vec3 adv = path(t + 0.7);
	float hd = de(adv);
	vec3 advec = normalize(adv - go);
	
	// Calculate rotation angles for camera orientation
	float an = adv.x - go.x;
	an *= min(1.0, abs(adv.z - go.z)) * sign(adv.z - go.z) * 0.7;
	dir.xy *= mat2(cos(an), sin(an), -sin(an), cos(an));
	
	an = advec.y * 1.7;
	dir.yz *= mat2(cos(an), sin(an), -sin(an), cos(an));
	
	an = atan(advec.x, advec.z);
	dir.xz *= mat2(cos(an), sin(an), -sin(an), cos(an));
	
	return go;
}

// ============================================================================
// MAIN RENDER FUNCTION
// ============================================================================

vec4 renderMain(void) {
	// Setup UV coordinates
	vec2 uv = _uv * 2. - 1.;
	vec2 oriuv = uv;
	uv.y *= RENDERSIZE.y / RENDERSIZE.x;
	
	// Dynamic FOV (zooms in over time)

	// Calculate ray direction
	vec3 dir = normalize(vec3(uv, FOV+0.5*zoom_pop));
	dir.xz *= rot(-0.05);
	
	// Calculate camera position and update direction
	vec3 from = origin + move(dir);
	
	// Raymarch scene
	vec3 color = raymarch(from, dir);
	// if (edges_mode==1.){
	// 	color = 1.0-color;
	// }
	// Optional border effect
	#ifdef BORDER
		color = mix(vec3(0.0), color, pow(max(0.0, 0.95 - length(oriuv * oriuv * oriuv * vec2(1.05, 1.1))), 0.3));
	#endif
	
	return vec4(color, 1.0);
}
