// all noise from iq!

const float IN_INNER = 0.2;
const float IN_OUTER = 0.2;
const float OUT_INNER = 0.2;
const float OUT_OUTER = 0.4; // 0.01 is nice too

float noise3D(vec3 p)
{
	return fract(sin(dot(p ,vec3(12.9898,78.233,128.852))) * 43758.5453)*2.0-1.0;
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

vec4 renderMoon()
{    
	vec2 fragCoord = _xy;
	vec2 centered = fragCoord - RENDERSIZE.xy * 0.5; // planet center

	vec3 lightDir = normalize(vec3(sin(syn_BassTime), sin(syn_BassTime * 0.5), cos(syn_BassTime)));

	float radius = RENDERSIZE.y / 3.0; // radius
	float distSq = dot(centered, centered);
	float dist = sqrt(distSq + 1e-6);
	float normalizedDist = clamp(dist / max(radius, 1e-3), 0.0, 1.0);
	float innerArg = max(radius * radius - distSq, 0.0);
	float zIn = sqrt(innerArg);

	bool inside = distSq <= radius * radius;
	float insideMask = inside ? 1.0 : 0.0;

	float zOut = 0.0;
	bool outside = distSq > radius * radius;
	if (outside)
	{
		zOut = sqrt(distSq - radius * radius);
	}

	vec3 norm = normalize(vec3(centered, max(zIn, 1e-3))); // normals from sphere
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
		zInnerAtmos = (radius * IN_OUTER) / max(zIn, 1e-3) - IN_INNER;   // inner atmos
		zInnerAtmos = max(0.0, zInnerAtmos);
	}

	float zOuterAtmos = 0.0;
	if (outside && zOut > 0.0)
	{
		zOuterAtmos = (radius * OUT_INNER) / zOut - OUT_OUTER; // outer atmos
		zOuterAtmos = max(0.0, zOuterAtmos);
	}

	float diffuse = max(0.0, dot(norm, lightDir));
	float diffuseOut = max(0.0, dot(normOut, lightDir) + 0.3); // +0.3 because outer atmosphere still shows

	float glowControl = mix(0.5, 1.5, atmosphere_mix); // slider controls glow contribution
	float spectrumPulse = texture(syn_Spectrum, normalizedDist).g;
	float trailPulse = texture(syn_LevelTrail, normalizedDist).r;
	float bassPulse = bass_react * (syn_BassLevel * 0.8 + syn_BassHits * 1.2);
	float midPulse = mid_react * (syn_MidLevel * 0.6 + syn_MidHighLevel * 0.4);
	float highPulse = high_react * (syn_HighLevel * 0.4 + syn_HighHits * 0.8);
	float bandPulse = bassPulse + midPulse + highPulse;
	float audioPulse = audio_reactivity * clamp(bandPulse + spectrumPulse * 0.8 + trailPulse * 0.6, 0.0, 2.5);
	vec3 audioTint = mix(vec3(1.0), vec3(0.7, 0.9, 1.3), clamp(audioPulse, 0.0, 1.5));
	float glowFactor = glowControl * (1.0 + audioPulse * 2.5);

	vec3 color = vec3(n * diffuse) * insideMask;
	color *= audioTint;
	float craterBoost = mix(1.0, 1.0 + audioPulse * 0.4, audio_reactivity);
	color *= craterBoost;
	color += glowFactor * (zInnerAtmos * diffuse + zOuterAtmos * diffuseOut);
	float rim = smoothstep(0.0, 0.6, 1.0 - dot(norm, -lightDir));
	float beatFlash = syn_OnBeat * 2.0;
	color += insideMask * (audioPulse + beatFlash) * rim * 0.5;

	float raySpread = mix(0.0, 0.8, audio_reactivity) * pow(1.0 - normalizedDist, 0.35);
	vec3 rayColor = vec3(0.3, 0.35, 0.55) * (spectrumPulse + syn_Presence) * raySpread;
	color += (1.0 - insideMask) * rayColor;

	float punchAmt = clamp(burstIntensity, 0.0, 1.0);
	vec3 burstColor = vec3(burstColorR, burstColorG, burstColorB);
	color = mix(color, burstColor * (1.5 + audioPulse), punchAmt);
	glowFactor += punchAmt * 1.8;
	color += glowFactor * punchAmt * 0.5;

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