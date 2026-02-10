// all noise from iq!

const float IN_INNER = 0.2;
const float IN_OUTER = 0.2;
const float OUT_INNER = 0.2;
const float OUT_OUTER = 0.4; // 0.01 is nice too

// Hash functions for particle system
float hash(float n) { return fract(sin(n) * 43758.5453); }
vec2 hash2(float n) { return vec2(hash(n), hash(n + 127.1)); }
float hash12(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

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

// Dust particles plus a short release ring when charge is released.
vec3 renderDustParticles(vec2 centered, float radius, float highHit)
{
	vec3 dustColor = vec3(0.0);
	float releaseAmount = dust_release;
	float chargedAmount = max(highHit, dust_charge * 0.75);
	float particleStrength = (chargedAmount * 0.8 + releaseAmount * 0.8) * dust_intensity;
	particleStrength *= mix(0.9, 2.25, dust_amount);
	if (particleStrength < 0.01) return dustColor;

	float rimStart = radius * 0.88;
	float rimEnd = radius * (1.0 + dust_spread * 2.6 + releaseAmount * 0.4);
	float dist = length(centered);
	float activeLayers = 1.0 + dust_amount * 2.0 + releaseAmount * 0.5;
	float beatStep = floor(syn_BeatTime * 2.0);
	float releaseStep = floor(dust_ring * 12.0) * 17.0;

	// Run particle loops only around moon rim to keep full-frame cost low.
	float particleZoneMin = rimStart - (28.0 + radius * 0.02);
	float particleZoneMax = rimEnd + (84.0 + releaseAmount * 64.0);
	bool inParticleZone = dist >= particleZoneMin && dist <= particleZoneMax;

	if (inParticleZone)
	{
		for (int layer = 0; layer < 3; layer++)
		{
			float layerMask = step(float(layer), activeLayers);
			if (layerMask < 0.5) continue;

			float layerOffset = float(layer) * 137.5;
			for (int i = 0; i < 8; i++)
			{
				float seed = float(i) + layerOffset + beatStep + releaseStep;
				float angle = hash(seed) * 6.28318;
				float angleSpread = mix(0.8, 6.28318, rim_glow);
				angle = mod(angle, angleSpread) - angleSpread * 0.5;
				angle += sin(TIME * (2.5 + float(layer) * 0.3) + seed) * (0.06 + 0.06 * releaseAmount);

				float radialT = hash(seed + 50.0);
				float radialPow = mix(2.0, 0.65, releaseAmount);
				float particleRadius = mix(rimStart, rimEnd, pow(radialT, radialPow));
				vec2 particlePos = vec2(cos(angle), sin(angle)) * particleRadius;
				float particleDist = length(centered - particlePos);

				float particleSize = mix(2.8, 13.5, hash(seed + 100.0));
				particleSize *= mix(0.85, 1.7, releaseAmount);
				float glow = particleSize / (particleDist * particleDist + 1.0);
				float radialFade = mix(1.0 - radialT, 1.0 - smoothstep(0.2, 1.0, radialT), releaseAmount);

				vec3 pColor = mix(
					vec3(0.80, 0.72, 0.58),
					vec3(0.58, 0.60, 0.68),
					hash(seed + 200.0)
				);
				dustColor += glow * radialFade * particleStrength * pColor * 0.2 * layerMask;
			}
		}
	}

	// Cheap continuous haze so max dust still feels thick without expensive loops.
	float angleBase = atan(centered.y, centered.x);
	float hazeBand = smoothstep(rimStart - 80.0, rimStart + 24.0, dist)
		* (1.0 - smoothstep(rimEnd + 95.0, rimEnd + 210.0, dist));
	float hazePattern = 0.5 + 0.5 * sin(angleBase * 17.0 + TIME * 1.7 + releaseStep * 0.03);
	hazePattern *= 0.65 + 0.35 * sin(angleBase * 33.0 - TIME * 1.1);
	float hazeStrength = hazeBand * hazePattern * (dust_amount * dust_intensity) * (0.22 + 0.55 * releaseAmount);
	dustColor += vec3(0.22, 0.22, 0.24) * hazeStrength;

	// Shock ring on release for a short "burst" feeling.
	if (releaseAmount > 0.001)
	{
		float ringRadius = mix(radius * 0.95, radius * (1.45 + dust_spread * 0.6), dust_ring);
		float ringWidth = mix(24.0, 52.0, dust_spread);
		float angle = atan(centered.y, centered.x);
		float angleNorm = (angle + 3.14159265) / 6.2831853;
		float sectorCount = 28.0;
		float sectorPos = angleNorm * sectorCount;
		float sectorIdx = floor(sectorPos);
		float sectorT = smoothstep(0.0, 1.0, fract(sectorPos));
		float n0 = hash(sectorIdx + releaseStep + 19.0) * 2.0 - 1.0;
		float n1 = hash(sectorIdx + 1.0 + releaseStep + 19.0) * 2.0 - 1.0;
		float randomDeform = mix(n0, n1, sectorT);
		float wavDeform = sin(angle * 7.0 + TIME * 1.4 + releaseStep * 0.07) * 0.45;
		float deformRadius = (randomDeform + wavDeform) * (8.0 + 22.0 * dust_spread) * (0.45 + releaseAmount * 0.55);
		float ringDelta = abs(dist - (ringRadius + deformRadius));
		if (ringDelta < ringWidth * 6.0)
		{
			float ring = exp(-ringDelta / ringWidth);
			dustColor += vec3(0.40, 0.38, 0.34) * ring * releaseAmount * 0.34;
		}
	}

	return dustColor;
}

float gridLine(float v, float w)
{
	return smoothstep(w, 0.0, abs(fract(v) - 0.5));
}

vec3 renderStarfield(vec2 uv, vec2 drift, float motion)
{
	vec3 col = vec3(0.0);
	float density = mix(0.25, 1.35, star_density);
	float speed = 0.02 + starfield_speed * 0.12 + motion * 0.04;
	float twinkleTime = TIME * (0.15 + starfield_speed * 0.45);

	for (int layer = 0; layer < 2; layer++)
	{
		float lf = float(layer);
		float scale = mix(90.0, 220.0, star_density) / (1.0 + lf * 0.9);
		vec2 layerUV = uv * scale;
		layerUV += drift * (9.0 + lf * 6.0);
		layerUV += vec2(speed * (1.0 + lf * 0.6), -speed * (0.7 + lf * 0.35)) * TIME * scale * 0.08;

		vec2 cell = floor(layerUV);
		vec2 local = fract(layerUV) - 0.5;
		float h = hash12(cell + lf * 37.13);
		vec2 clusterCell = floor(cell / 7.0);
		float clusterSeed = hash12(clusterCell + lf * 13.0);
		vec2 clusterCenter = hash2(clusterSeed * 91.73) * 7.0;
		vec2 inCluster = fract(cell / 7.0) * 7.0 - clusterCenter;
		float clusterFalloff = exp(-dot(inCluster, inCluster) * 0.22);
		float clusterActive = step(0.74, clusterSeed);
		float clusterBoost = clusterActive * clusterFalloff;

		float threshold = 1.0 - (0.005 + 0.010 * density / (1.0 + lf) + 0.025 * clusterBoost);
		float spawn = step(threshold, h);
		float giant = step(0.988, h + clusterBoost * 0.06);
		float size = mix(0.03, 0.24, pow(h, 1.2));
		size = mix(size, 0.44 + 0.22 * clusterBoost, giant);
		float star = smoothstep(size, 0.0, length(local)) * spawn;
		float twinkle = 0.7 + 0.3 * sin(twinkleTime * (1.1 + h * 2.4) + h * 40.0);
		float depthFade = 1.0 / (1.0 + lf * 1.4);
		vec3 tint = mix(vec3(0.62, 0.66, 0.72), vec3(0.95, 0.94, 0.90), h * h);
		tint = mix(tint, vec3(0.78, 0.83, 0.94), clusterBoost * 0.7);
		col += tint * star * twinkle * depthFade * (0.95 + clusterBoost * 0.65);
	}
	return col * space_brightness;
}

vec3 renderDeepGrid(vec2 uv, vec2 drift, float motion)
{
	if (grid_visibility <= 0.001) return vec3(0.0);

	float aspect = RENDERSIZE.x / RENDERSIZE.y;
	vec2 p = uv + drift * 0.08;
	p.x *= aspect;

	float horizon = -0.03 + motion * 0.03;
	float y = max(p.y - horizon + 0.55, 0.08);
	float perspective = 1.0 / y;

	float density = mix(4.0, 12.0, grid_density);
	float travel = TIME * (0.06 + grid_speed * 0.28 + motion * 0.12);
	float sideDrift = TIME * (0.01 + grid_speed * 0.06) + drift.x * 1.5;
	vec2 g = vec2(
		(p.x + sideDrift) * perspective * density,
		perspective * density * 0.7 + travel
	);

	float lineW = mix(0.08, 0.03, grid_density);
	float lines = max(gridLine(g.x, lineW), gridLine(g.y, lineW * 0.9));
	float scan = gridLine(g.y + TIME * (0.16 + motion * 0.1), lineW * 0.55) * 0.35;

	float fadeFar = smoothstep(1.2, 4.8, perspective);
	float fadeNear = 1.0 - smoothstep(5.2, 10.0, perspective);
	float fadeVertical = smoothstep(-0.4, 0.9, p.y) * (1.0 - smoothstep(0.85, 1.35, p.y));
	float fade = fadeFar * fadeNear * fadeVertical;

	vec3 gridCol = vec3(0.20, 0.23, 0.28) * (lines + scan);
	return gridCol * fade * grid_visibility * space_brightness * 0.7;
}

vec3 renderMeteor(vec2 uv, vec2 drift)
{
	if (meteor_active < 0.5) return vec3(0.0);

	vec2 dir = normalize(vec2(meteor_dir_x, meteor_dir_y) + vec2(1e-5, 1e-5));
	vec2 p = uv + drift * 0.06;
	vec2 pos = vec2(meteor_pos_x, meteor_pos_y);
	vec2 rel = p - pos;

	float along = dot(rel, dir);
	float perp = length(rel - dir * along);
	float tailLen = max(0.16, meteor_length);
	float tail = exp(along / tailLen) * step(along, 0.0) * smoothstep(-tailLen * 1.6, -0.02, along);
	float head = exp(-perp * 38.0) * exp(-abs(along) * 15.0);
	float streak = exp(-perp * 18.0) * tail;
	float sparkle = 0.75 + 0.25 * sin(TIME * 40.0 + along * 120.0);

	float alpha = (head * 1.55 + streak * 1.25 * sparkle) * meteor_strength * 1.35;
	vec3 c = mix(vec3(0.78, 0.80, 0.86), vec3(1.0, 0.98, 0.92), head);
	return c * alpha;
}

vec3 renderSpaceBackground(vec2 centered)
{
	vec2 uv = centered / RENDERSIZE.y;
	vec2 drift = vec2(bg_drift_x, bg_drift_y);
	float motion = bg_motion;
	vec3 base = vec3(0.006, 0.008, 0.012) * space_brightness;
	vec3 stars = renderStarfield(uv, drift, motion);
	vec3 grid = renderDeepGrid(uv, drift, motion);
	vec3 meteor = renderMeteor(uv, drift);
	return base + stars + grid + meteor;
}

vec4 renderMoon()
{    
	vec2 fragCoord = _xy;
	vec2 centered = fragCoord - RENDERSIZE.xy * 0.5; // planet center
	vec3 backgroundColor = renderSpaceBackground(centered);

	vec3 lightDir = normalize(vec3(sin(syn_BassTime), sin(syn_BassTime * 0.5), cos(syn_BassTime)));

	float radius = RENDERSIZE.y / 3.0; // radius
	
	// === BASS WOBBLE DEFORMATION ===
	// Script-smoothed drive keeps wobble fluid while hits add only a subtle accent.
	float wobbleDrive = clamp(wobble_drive, 0.0, 1.5);
	float wobbleHit = clamp(wobble_hit, 0.0, 1.0);
	float bassWobble = (wobbleDrive * 0.95 + wobbleHit * 0.15) * wobble_intensity;
	bassWobble = max(bassWobble, syn_BassLevel * wobble_intensity * 0.18);
	
	// Calculate radial position for rim-focused wobble
	float distFromCenter = length(centered);
	float radialT = clamp(distFromCenter / radius, 0.0, 1.0);
	// Rim falloff: 0 at center, ramps up toward rim (power curve for sharper transition)
	float rimFalloff = pow(radialT, 2.5);
	
	// Lower-frequency phase blend gives smoother liquid motion.
	float flowT = TIME * wobble_speed;
	float wobblePhase1 = sin(flowT * 2.2) * bassWobble;
	float wobblePhase2 = sin(flowT * 3.5 + 1.0) * bassWobble * 0.55;
	float wobblePhase3 = cos(flowT * 4.8 + 2.2) * bassWobble * 0.25;
	
	// Directional wobble with seam-safe integer harmonics (no atan branch cut seam).
	float angle = atan(centered.y, centered.x);
	float wobbleAmount = wobblePhase1 * sin(angle * 2.0 + flowT * 0.8) 
	                   + wobblePhase2 * sin(angle * 3.0 - flowT * 0.65)
	                   + wobblePhase3 * cos(angle * 4.0 + flowT * 0.52);
	float liquidDrift = sin(angle + flowT * 0.34) * sin(angle * 2.0 - flowT * 0.21);
	wobbleAmount += liquidDrift * bassWobble * 0.18;
	
	// Apply rim falloff - center stays static, rim wobbles
	wobbleAmount *= rimFalloff;
	
	// Apply wobble to radius (reduced amplitude avoids frame-to-frame edge pops).
	float wobbledRadius = radius * (1.0 + wobbleAmount * 0.09);
	
	float distSq = dot(centered, centered);
	float dist = sqrt(distSq + 1e-6);
	float signedEdge = dist - wobbledRadius;
	float edgeAA = max(1.25, fwidth(dist) * 2.0 + 0.75);
	float insideMask = 1.0 - smoothstep(-edgeAA, edgeAA, signedEdge);
	float outsideMask = 1.0 - insideMask;
	float normalizedDist = clamp(dist / max(wobbledRadius, 1e-3), 0.0, 1.0);
	float innerArg = max(wobbledRadius * wobbledRadius - distSq, 0.0);
	float zIn = sqrt(innerArg);

	bool inside = insideMask > 0.001;
	float zOut = sqrt(max(distSq - wobbledRadius * wobbledRadius, 0.0));

	vec3 norm = normalize(vec3(centered, max(zIn, 1e-3))); // normals from sphere
	
	// Add wobble displacement to normals for surface ripple effect (only at rim)
	float normalWobble = bassWobble * 0.16 * rimFalloff;
	norm.x += sin(angle * 2.0 + flowT * 2.7) * normalWobble;
	norm.y += cos(angle * 3.0 - flowT * 2.2) * normalWobble;
	norm = normalize(norm);
	
	vec3 normOut = normalize(vec3(centered, max(zOut, 1e-3))); // normals from outside sphere
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
		zInnerAtmos = max(0.0, zInnerAtmos) * insideMask;
	}

	float zOuterAtmos = 0.0;
	if (zOut > 0.0)
	{
		zOuterAtmos = (wobbledRadius * OUT_INNER) / zOut - OUT_OUTER; // outer atmos
		zOuterAtmos = max(0.0, zOuterAtmos) * outsideMask;
	}

	float diffuse = max(0.0, dot(norm, lightDir));
	float diffuseOut = max(0.0, dot(normOut, lightDir) + 0.3); // +0.3 because outer atmosphere still shows

	float glowControl = mix(0.5, 1.5, atmosphere_mix); // slider controls glow contribution
	vec3 moonSurfaceColor = vec3(n * diffuse);

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
		moonSurfaceColor = mix(moonSurfaceColor, mediaCol, media_blend * limbMask);
	}

	vec3 color = mix(backgroundColor, moonSurfaceColor, insideMask);

	// Add atmosphere glow
	color += glowControl * (zInnerAtmos * diffuse + zOuterAtmos * diffuseOut);
	color += vec3(0.18, 0.18, 0.2) * dust_release * (zInnerAtmos + zOuterAtmos) * 0.12;
	
	// === DUST PARTICLES ===
	// Triggered by highs and script-driven charge/release state.
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
