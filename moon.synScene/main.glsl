// all noise from iq!

const float IN_INNER = 0.2;
const float IN_OUTER = 0.2;
const float OUT_INNER = 0.2;
const float OUT_OUTER = 0.4; // 0.01 is nice too

// Hash functions for particle system
float hash(float n) { return fract(sin(n) * 43758.5453); }
vec2 hash2(float n) { return vec2(hash(n), hash(n + 127.1)); }

// Particle state tracking (simple exponential decay envelope)
float particleEnvelope(float hitTime, float decay)
{
	float t = TIME - hitTime;
	return exp(-t * decay) * step(0.0, t);
}

float noise3D(vec3 p)
{
	// Improved hash to reduce banding artifacts
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z) * 2.0 - 1.0;
}

float simplex3D(vec3 p)
{
	float f3 = 1.0/3.0;
	float s = (p.x+p.y+p.z)*f3;
	int i = int(floor(p.x+s));
	int j = int(floor(p.y+s));
	int k = int(floor(p.z+s));
	
	float g3 = 1.0/6.0;
	float t = float((i+j+k))*g3;
	float x0 = float(i)-t;
	float y0 = float(j)-t;
	float z0 = float(k)-t;
	x0 = p.x-x0;
	y0 = p.y-y0;
	z0 = p.z-z0;
	int i1,j1,k1;
	int i2,j2,k2;
	if(x0>=y0)
	{
		if		(y0>=z0){ i1=1; j1=0; k1=0; i2=1; j2=1; k2=0; } // X Y Z order
		else if	(x0>=z0){ i1=1; j1=0; k1=0; i2=1; j2=0; k2=1; } // X Z Y order
		else 			{ i1=0; j1=0; k1=1; i2=1; j2=0; k2=1; } // Z X Z order
	}
	else 
	{ 
		if		(y0<z0) { i1=0; j1=0; k1=1; i2=0; j2=1; k2=1; } // Z Y X order
		else if	(x0<z0) { i1=0; j1=1; k1=0; i2=0; j2=1; k2=1; } // Y Z X order
		else 			{ i1=0; j1=1; k1=0; i2=1; j2=1; k2=0; } // Y X Z order
	}
	float x1 = x0 - float(i1) + g3; 
	float y1 = y0 - float(j1) + g3;
	float z1 = z0 - float(k1) + g3;
	float x2 = x0 - float(i2) + 2.0*g3; 
	float y2 = y0 - float(j2) + 2.0*g3;
	float z2 = z0 - float(k2) + 2.0*g3;
	float x3 = x0 - 1.0 + 3.0*g3; 
	float y3 = y0 - 1.0 + 3.0*g3;
	float z3 = z0 - 1.0 + 3.0*g3;			 
	vec3 ijk0 = vec3(i,j,k);
	vec3 ijk1 = vec3(i+i1,j+j1,k+k1);	
	vec3 ijk2 = vec3(i+i2,j+j2,k+k2);
	vec3 ijk3 = vec3(i+1,j+1,k+1);	     
	vec3 gr0 = normalize(vec3(noise3D(ijk0),noise3D(ijk0*2.01),noise3D(ijk0*2.02)));
	vec3 gr1 = normalize(vec3(noise3D(ijk1),noise3D(ijk1*2.01),noise3D(ijk1*2.02)));
	vec3 gr2 = normalize(vec3(noise3D(ijk2),noise3D(ijk2*2.01),noise3D(ijk2*2.02)));
	vec3 gr3 = normalize(vec3(noise3D(ijk3),noise3D(ijk3*2.01),noise3D(ijk3*2.02)));
	float n0 = 0.0;
	float n1 = 0.0;
	float n2 = 0.0;
	float n3 = 0.0;
	float t0 = 0.5 - x0*x0 - y0*y0 - z0*z0;
	if(t0>=0.0)
	{
		t0*=t0;
		n0 = t0 * t0 * dot(gr0, vec3(x0, y0, z0));
	}
	float t1 = 0.5 - x1*x1 - y1*y1 - z1*z1;
	if(t1>=0.0)
	{
		t1*=t1;
		n1 = t1 * t1 * dot(gr1, vec3(x1, y1, z1));
	}
	float t2 = 0.5 - x2*x2 - y2*y2 - z2*z2;
	if(t2>=0.0)
	{
		t2 *= t2;
		n2 = t2 * t2 * dot(gr2, vec3(x2, y2, z2));
	}
	float t3 = 0.5 - x3*x3 - y3*y3 - z3*z3;
	if(t3>=0.0)
	{
		t3 *= t3;
		n3 = t3 * t3 * dot(gr3, vec3(x3, y3, z3));
	}
	return 96.0*(n0+n1+n2+n3);
}

float fbm(vec3 p)
{
	float f;
    f  = 0.50000*(simplex3D( p )); p = p*2.01;
    f += 0.25000*(simplex3D( p )); p = p*2.02;
    f += 0.12500*(simplex3D( p )); p = p*2.03;
    f += 0.06250*(simplex3D( p )); p = p*2.04;
    f += 0.03125*(simplex3D( p )); p = p*2.05;
    f += 0.015625*(simplex3D( p ));
	return f;
}

vec2 rotate2D(vec2 p, float angle)
{
	float c = cos(angle);
	float s = sin(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Render dust particles ejected from moon rim
vec3 renderDustParticles(vec2 centered, float radius, float highHit)
{
	vec3 dustColor = vec3(0.0);
	
	// Only spawn particles when we have a high hit
	float particleStrength = highHit * dust_intensity;
	if (particleStrength < 0.01) return dustColor;
	
	// Ring zone around the moon where particles appear
	float dist = length(centered);
	float rimStart = radius * 0.9;
	float rimEnd = radius * (1.0 + dust_spread * 2.0);
	
	// Multiple particle layers for density
	for (int layer = 0; layer < 3; layer++)
	{
		float layerOffset = float(layer) * 137.5; // golden angle spread
		
		// 12 particles per layer
		for (int i = 0; i < 12; i++)
		{
			float seed = float(i) + layerOffset + floor(syn_BeatTime * 2.0);
			
			// Random angle around the rim
			float angle = hash(seed) * 6.28318;
			// Apply rim_glow to control angular coverage (0 = thin, 1 = full circle)
			float angleSpread = mix(1.0, 6.28318, rim_glow);
			angle = mod(angle, angleSpread) - angleSpread * 0.5;
			
			// Random radial distance (ejected outward)
			float radialT = hash(seed + 50.0);
			float particleRadius = mix(rimStart, rimEnd, radialT * radialT);
			
			// Add some wobble to make it organic
			float wobbleAngle = sin(TIME * 3.0 + seed) * 0.1;
			angle += wobbleAngle;
			
			// Particle position
			vec2 particlePos = vec2(cos(angle), sin(angle)) * particleRadius;
			
			// Distance to this particle
			float particleDist = length(centered - particlePos);
			
			// Particle size varies
			float particleSize = mix(2.0, 8.0, hash(seed + 100.0));
			
			// Soft particle glow
			float glow = particleSize / (particleDist * particleDist + 1.0);
			
			// Fade based on how far from rim (newly ejected = bright)
			float radialFade = 1.0 - radialT;
			
			// Color variation (sandy/dusty tones)
			vec3 pColor = mix(
				vec3(0.8, 0.7, 0.5), // sand
				vec3(0.6, 0.6, 0.7), // lunar dust
				hash(seed + 200.0)
			);
			
			dustColor += glow * radialFade * particleStrength * pColor * 0.15;
		}
	}
	
	return dustColor;
}

vec4 renderMoon()
{    
	vec2 fragCoord = _xy;
	vec2 centered = fragCoord - RENDERSIZE.xy * 0.5; // planet center

	vec3 lightDir = normalize(vec3(sin(syn_BassTime), sin(syn_BassTime * 0.5), cos(syn_BassTime)));

	float radius = RENDERSIZE.y / 3.0; // radius
	
	// === BASS WOBBLE DEFORMATION ===
	// Combine smooth bass level with transient hits for rubber-like behavior
	float bassWobble = syn_BassLevel * 0.7 + syn_BassHits * 1.5;
	bassWobble *= wobble_intensity;
	
	// Calculate radial position for rim-focused wobble
	float distFromCenter = length(centered);
	float radialT = clamp(distFromCenter / radius, 0.0, 1.0);
	// Rim falloff: 0 at center, ramps up toward rim (power curve for sharper transition)
	float rimFalloff = pow(radialT, 2.5);
	
	// Multiple wobble frequencies for organic rubber feel
	float wobblePhase1 = sin(TIME * wobble_speed * 4.0) * bassWobble;
	float wobblePhase2 = sin(TIME * wobble_speed * 6.3 + 1.0) * bassWobble * 0.6;
	float wobblePhase3 = cos(TIME * wobble_speed * 8.7 + 2.0) * bassWobble * 0.3;
	
	// Directional wobble - different amounts in x and y for jelly effect
	float angle = atan(centered.y, centered.x);
	float wobbleAmount = wobblePhase1 * sin(angle * 2.0 + TIME * wobble_speed) 
	                   + wobblePhase2 * sin(angle * 3.0 - TIME * wobble_speed * 1.3)
	                   + wobblePhase3 * cos(angle * 4.0 + TIME * wobble_speed * 0.7);
	
	// Apply rim falloff - center stays static, rim wobbles
	wobbleAmount *= rimFalloff;
	
	// Apply wobble to radius (makes sphere bulge/contract directionally)
	float wobbledRadius = radius * (1.0 + wobbleAmount * 0.15);
	
	float distSq = dot(centered, centered);
	float dist = sqrt(distSq + 1e-6);
	float normalizedDist = clamp(dist / max(wobbledRadius, 1e-3), 0.0, 1.0);
	float innerArg = max(wobbledRadius * wobbledRadius - distSq, 0.0);
	float zIn = sqrt(innerArg);

	bool inside = distSq <= wobbledRadius * wobbledRadius;
	float insideMask = inside ? 1.0 : 0.0;

	float zOut = 0.0;
	bool outside = distSq > wobbledRadius * wobbledRadius;
	if (outside)
	{
		zOut = sqrt(distSq - wobbledRadius * wobbledRadius);
	}

	vec3 norm = normalize(vec3(centered, max(zIn, 1e-3))); // normals from sphere
	
	// Add wobble displacement to normals for surface ripple effect (only at rim)
	float normalWobble = bassWobble * 0.3 * rimFalloff;
	norm.x += sin(angle * 3.0 + TIME * wobble_speed * 5.0) * normalWobble;
	norm.y += cos(angle * 2.0 - TIME * wobble_speed * 4.0) * normalWobble;
	norm = normalize(norm);
	
	vec3 normOut = outside ? normalize(vec3(centered, zOut)) : norm; // normals from outside sphere
	float e = 0.05; // planet rugosity
	float nx = fbm(vec3(norm.x + e, norm.y, norm.z)) * 0.5 + 0.5; // x normal displacement
	float ny = fbm(vec3(norm.x, norm.y + e, norm.z)) * 0.5 + 0.5; // y normal displacement
	float nz = fbm(vec3(norm.x, norm.y, norm.z + e)) * 0.5 + 0.5; // z normal displacement
	norm = normalize(vec3(norm.x * nx, norm.y * ny, norm.z * nz));

	float n = 1.0 - (fbm(norm) * 0.5 + 0.5); // noise for every pixel in planet

	float zInnerAtmos = 0.0;
	if (zIn > 0.0)
	{
		zInnerAtmos = (wobbledRadius * IN_OUTER) / max(zIn, 1e-3) - IN_INNER;   // inner atmos
		zInnerAtmos = max(0.0, zInnerAtmos);
	}

	float zOuterAtmos = 0.0;
	if (outside && zOut > 0.0)
	{
		zOuterAtmos = (wobbledRadius * OUT_INNER) / zOut - OUT_OUTER; // outer atmos
		zOuterAtmos = max(0.0, zOuterAtmos);
	}

	float diffuse = max(0.0, dot(norm, lightDir));
	float diffuseOut = max(0.0, dot(normOut, lightDir) + 0.3); // +0.3 because outer atmosphere still shows

	float glowControl = mix(0.5, 1.5, atmosphere_mix); // slider controls glow contribution

	vec3 color = vec3(n * diffuse) * insideMask;

	// Media projection with cubemap-style UVs
	if (inside && media_blend > 0.0)
	{
		// Front-facing cubemap projection using sphere normals
		vec2 mediaUV = norm.xy * 0.5 + 0.5;
		
		// Animated rotation
		mediaUV -= 0.5;
		mediaUV = rotate2D(mediaUV, TIME * media_rotation_speed);
		mediaUV *= media_scale;
		mediaUV += 0.5;
		
		// Subtle wobble-driven distortion on media (kept minimal for clarity)
		float distortAmt = media_distortion * bassWobble * 0.3;
		vec2 noiseOffset = vec2(
			fbm(vec3(mediaUV * 3.0, TIME * 0.5)) * distortAmt * 0.03,
			fbm(vec3(mediaUV.yx * 3.0, TIME * 0.5 + 10.0)) * distortAmt * 0.03
		);
		mediaUV += noiseOffset;
		
		// Sample media
		vec3 mediaCol = texture(syn_Media, mediaUV).rgb;
		
		// Apply diffuse shading to media
		mediaCol *= diffuse * 0.8 + 0.2; // Keep some ambient so it's visible
		
		// Limb fade - fade media at sphere edges
		float viewDot = max(0.0, norm.z); // front-facing = 1, edge = 0
		float limbMask = smoothstep(0.0, 0.5 + media_limb_fade * 0.5, viewDot);
		
		// Blend media with surface
		color = mix(color, mediaCol, media_blend * limbMask);
	}

	// Add atmosphere glow
	color += glowControl * (zInnerAtmos * diffuse + zOuterAtmos * diffuseOut);
	
	// === DUST PARTICLES ===
	// Triggered by high frequency hits (peaks)
	float highHit = syn_HighHits + syn_MidHighHits * 0.5;
	vec3 dustParticles = renderDustParticles(centered, wobbledRadius, highHit);
	color += dustParticles;

	return vec4(color, 1.0);
}

vec4 renderMain()
{
	if (PASSINDEX == 0)
	{
		return renderMoon();
	}
	return vec4(0.0);
}