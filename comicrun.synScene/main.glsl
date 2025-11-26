#define FAR 400.0
#define EDGE_WIDTH_BASE 0.005
#define MAX_TRACE_STEPS 128
#define MAX_SHADOW_STEPS 16

#define ID_SKY    0.0
#define ID_SHIP   1.0
#define ID_GROUND 2.0
#define ID_PATH   3.0

const float freqA = 0.34 * 0.15 / 3.75;
const float freqB = 0.25 * 0.25 / 2.75;
const float ampA = 20.0;
const float ampB = 4.0;
const vec2 CARTOON_BUFFER_RES = vec2(1280.0, 720.0);

vec3 gRO;
mat3 gbaseShip;
float gedge;
float gedge2;
float glastt;
float gEdgeWidth;

mat2 rot2(float th)
{
	vec2 a = sin(vec2(1.5707963, 0.0) + th);
	return mat2(a, -a.y, a.x);
}

float hash11(float n)
{
	return fract(cos(n) * 45758.5453);
}

float hash21(vec2 p)
{
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash31(vec3 p)
{
	return fract(sin(dot(p, vec3(7.0, 157.0, 113.0))) * 45758.5453);
}

float noise(vec2 p)
{
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i + vec2(0.0, 0.0));
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p)
{
	float f = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; ++i)
	{
		f += amp * noise(p);
		p = p * 2.02;
		amp *= 0.5;
	}
	return f;
}

float smaxP(float a, float b, float s)
{
	float h = clamp(0.5 + 0.5 * (a - b) / s, 0.0, 1.0);
	return mix(b, a, h) + h * (1.0 - h) * s;
}

float sdVerticalCapsule(vec3 p, float h, float r)
{
	p.y -= clamp(p.y, 0.0, h);
	return length(p) - r;
}

float sdTorus(vec3 p, vec2 t)
{
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

float sdBox(vec3 p, vec3 b)
{
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdBox(vec2 p, vec2 b)
{
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdCappedCylinder(vec3 p, float h, float r)
{
	vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(h, r);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

void pModPolar(inout vec2 p, float repetitions)
{
	float angle = 6.2831853 / repetitions;
	float a = atan(p.y, p.x) + angle * 0.5;
	a = mod(a, angle) - angle * 0.5;
	p = vec2(cos(a), sin(a)) * length(p);
}

void pR45(inout vec2 p)
{
	p = (p + vec2(p.y, -p.x)) * 0.70710678;
}

vec2 path(float z)
{
	return vec2(ampA * sin(z * freqA) + 2.0 * cos(z * 0.0252) - 1.0,
	            10.0 + ampB * cos(z * freqB) * (0.5 + 0.5 * sin(z * 0.0015)));
}

float texScrape(vec2 uv)
{
	float n = fbm(uv);
	float detail = fbm(uv * 2.7 + vec2(0.3, 0.7));
	return mix(n, detail, 0.6);
}

float sdGround(vec3 p)
{
	p += vec3(0.0, 2.0, 0.0);
	float tx1 = 2.5 * texScrape(p.xz / 28.0 + p.xy / 100.0);
	float tx2 = 2.0 * texScrape(p.xy / vec2(31.0, 15.0));
	float tx = tx1 - tx2;

	vec3 q = p * 0.125;
	float h = dot(sin(q) * cos(q.yzx), vec3(0.222)) + dot(sin(q * 1.5) * cos(q.yzx * 1.5), vec3(0.111));

	float d = p.y + h * 6.0;
	q = p * 0.07125;
	float h3 = dot(sin(q) * cos(q.yzx), vec3(0.222)) + dot(sin(q * 1.5) * cos(q.yzx * 1.5), vec3(0.111));
	float d3 = p.y + h3 * 22.0 - 22.0;

	q = sin(p * 0.5 + h);
	float h2 = q.x * q.y * q.z;

	vec3 p0 = p;
	p.xy -= path(p.z);
	float dPath = length(p.xy) - 38.0;
	vec3 p1 = p;
	float tnl = 1.5 - length(p.xy * vec2(1.2, 1.96)) + h2;

	p.xz = mod(p0.xz + 150.0, 300.0) - 150.0;
	float dCaps = mix(999.0, sdVerticalCapsule(p + vec3(45.0, 60.0, 50.0), 130.0, 15.0) + tx1, step(2500.0, p0.z));

	p = p1;
	p.z = mod(p.z + 250.0, 500.0) - 250.0;
	float dGate = sdTorus(p.yzx - vec3(25.0, 25.0, 5.0), vec2(50.0, 15.0)) + tx1;
	dCaps = mix(dCaps, dGate, step(4600.0, p0.z));

	p.xz = mod(p0.xz + 450.0, 900.0) - 450.0;
	float dCaps2 = sdVerticalCapsule(p + vec3(20.0, 55.0, 0.0), 100.0, 30.0) + 0.5 * tx;

	float d4 = smaxP(d - tx * 0.5 + tnl * 0.4, 0.2 * tnl, 8.0);
	d3 = mix(d3, d4, smoothstep(0.5, 1.0, 0.5 + 0.5 * (sin(p0.z * 0.001 - 0.8))));

	d = min(dCaps, smaxP(d3, d4, 10.0));
	float dend = max(p0.y - 60.0, -dPath - 0.5 * tx + 0.25 * tx2);
	d = mix(d, dend, smoothstep(7000.0, 9000.0, p0.z) * smoothstep(12000.0, 9000.0, p0.z));
	d = smaxP(-dCaps2, d, 2.0);
	return d;
}

float sdShip(vec3 p0)
{
	p0 -= vec3(4.0, 0.0, 0.0);
	float d = length(p0) - 4.0;
	vec3 pRot = p0;
	pModPolar(pRot.zy, 16.0);
	pRot.x = abs(pRot.x);
	d = min(d, length(pRot - vec3(2.6, 0.0, 3.0)) - 0.2);
	d = min(d, sdBox(pRot - vec3(4.5, 0.0, 0.8), vec3(0.5, 0.1, 0.2)));

	vec3 p = p0;
	p.zy = abs(p.zy);
	p -= vec3(-5.6, 2.5, 2.0);
	pR45(p.yz);
	pR45(p.xy);
	return min(d, sdBox(p, vec3(1.0, 2.0, 0.2)));
}

float sdPath(vec3 p0)
{
	float d2 = length(path(p0.z) - p0.xy) - 0.5;
	return max(d2, -gRO.z + p0.z);
}

float map(vec3 p0)
{
	float d = sdGround(p0);
	float dPath = sdPath(p0 - vec3(0.0));
	return min(dPath, d);
}

float mapFull(vec3 p0)
{
	float d = sdGround(p0);
	float dPath = sdPath(p0);
	return min(sdShip((p0 - gRO) * gbaseShip), min(dPath, d));
}

vec2 min2(vec2 c0, vec2 c1)
{
	return c0.x < c1.x ? c0 : c1;
}

vec2 mapColor(vec3 p0)
{
	float d = sdGround(p0);
	float dPath = sdPath(p0);
	return min2(vec2(sdShip((p0 - gRO) * gbaseShip), ID_SHIP),
	            min2(vec2(dPath, ID_PATH), vec2(d, ID_GROUND)));
}

float logBisectTrace(vec3 ro, vec3 rd)
{
	float t = 0.0;
	float told = 0.0;
	float mid;
	float d = map(rd * t + ro);
	float sgn = sign(d);
	float lastDistEval = 1e10;
	float lastt = 0.0;
	vec3 rdShip = rd * gbaseShip;
	vec3 roShip = (ro - gRO) * gbaseShip;

	for (int i = 0; i < MAX_TRACE_STEPS; ++i)
	{
		if (sign(d) != sgn || d < 0.01 || t > FAR)
		{
			break;
		}

		told = t;
		t += step(d, 1.0) * (log(abs(d) + 1.1) - d) + d;
		d = map(rd * t + ro);
		d = min(d, sdShip(rdShip * t + roShip));

		if (d < lastDistEval)
		{
			lastt = t;
			lastDistEval = d;
		}
		else
		{
			float farMix = mix(30.0, lastt, smoothstep(FAR * 0.75, FAR * 0.9, t));
			if (d > lastDistEval + 0.0001 && lastDistEval / farMix < gEdgeWidth)
			{
				gedge = 1.0;
				if (glastt == 0.0)
				{
					glastt = lastt;
				}
			}
			if (d > lastDistEval + 0.0001 && (lastDistEval < gEdgeWidth * 40.0 || lastDistEval / lastt < gEdgeWidth * 2.0))
			{
				gedge2 = 1.0;
			}
		}
	}
	if (glastt == 0.0)
	{
		glastt = lastt;
	}
	return min(t, FAR);
}

vec3 normal(vec3 p)
{
	vec2 e = vec2(-1.0, 1.0) * 0.001;
	return normalize(e.yxx * mapFull(p + e.yxx) + e.xxy * mapFull(p + e.xxy) +
	                 e.xyx * mapFull(p + e.xyx) + e.yyy * mapFull(p + e.yyy));
}

float softShadow(vec3 ro, vec3 rd, float start, float end, float k)
{
	ro += rd * hash31(ro);
	vec3 rdShip = rd * gbaseShip;
	vec3 roShip = (ro - gRO) * gbaseShip;
	float shade = 1.0;
	float dist = start;
	float stepDist = end / float(MAX_SHADOW_STEPS);
	for (int i = 0; i < MAX_SHADOW_STEPS; ++i)
	{
		float h = min(map(ro + rd * dist), sdShip(roShip + dist * rdShip));
		shade = min(shade, smoothstep(0.0, 1.0, k * h / dist));
		dist += clamp(h, 0.2, stepDist * 2.0);
		if (abs(h) < 0.001 || dist > end)
		{
			break;
		}
	}
	return min(max(shade, 0.0) + 0.1, 1.0);
}

vec3 getSky(vec3 ro, vec3 rd, vec3 sunDir)
{
	return vec3(smoothstep(0.97, 1.0, max(dot(rd, sunDir), 0.0)));
}

float curve(vec3 p)
{
	const float eps = 0.05;
	const float amp = 4.0;
	const float ampInit = 0.5;
	vec2 e = vec2(-1.0, 1.0) * eps;
	float t1 = mapFull(p + e.yxx);
	float t2 = mapFull(p + e.xxy);
	float t3 = mapFull(p + e.xyx);
	float t4 = mapFull(p + e.yyy);
	return clamp((t1 + t2 + t3 + t4 - 4.0 * mapFull(p)) * amp + ampInit, 0.0, 1.0);
}

vec4 renderScene(vec2 fragCoord, vec2 resolution)
{
	gedge = 0.0;
	gedge2 = 0.0;
	glastt = 0.0;
	float edgeSlider = clamp(edge_width_scale, 0.0, 1.0);
	gEdgeWidth = mix(EDGE_WIDTH_BASE * 0.35, EDGE_WIDTH_BASE * 2.4, edgeSlider);

	vec2 u = (fragCoord - resolution.xy * 0.5) / resolution.y;
	float dBox = sdBox(u, vec2(0.5 * resolution.x / resolution.y - 0.1, 0.4));
	vec3 col = vec3(0.2);
	float ed = 0.0;
	float ed2 = 0.0;
	float lastt1 = 0.0;
	float toneShift = mix(-0.25, 0.65, tone_shift);
	vec2 normUV = clamp(fragCoord / resolution, 0.0, 1.0);
	float bassPulse = audio_reactivity * bass_emphasis * clamp(syn_BassLevel * 0.9 + syn_BassHits * 1.4, 0.0, 2.5);
	float midPulse = audio_reactivity * clamp(syn_MidLevel * 0.8 + syn_MidHighHits * 0.9, 0.0, 2.5);
	float highPulse = audio_reactivity * high_emphasis * clamp(syn_HighLevel * 0.7 + syn_HighHits * 1.2, 0.0, 2.5);
	float levelPulse = audio_reactivity * clamp(syn_Level, 0.0, 1.0);
	float beatPulse = audio_reactivity * syn_OnBeat;
	float spectrumSweep = texture(syn_Spectrum, normUV.x).g;
	float trailBass = texture(syn_LevelTrail, normUV.x).g;
	float audioDrive = clamp(levelPulse + 0.5 * bassPulse, 0.0, 2.0);
	vec2 audioSway = vec2(sin(TIME * 0.35 + spectrumSweep * 6.2831), cos(TIME * 0.22 + trailBass * 4.5));

	if (dBox < 0.0)
	{
		vec3 lookAt = vec3(0.0, 0.0, TIME * 100.0 * flight_speed);
		vec3 ro = lookAt + vec3(0.0, 0.0, -0.25);
		vec2 pathLook = path(lookAt.z);
		vec2 pathRo = path(ro.z);
		lookAt.xy += pathLook * (1.0 + 0.35 * bassPulse) + audioSway * 6.0 * bassPulse;
		ro.xy += pathRo * (1.0 + 0.25 * midPulse) + audioSway * 4.0 * bassPulse;
	lookAt.y -= 0.071 - 0.4 * beatPulse + camera_tilt * 10.0;
		float FOV = 1.5707963 * (1.0 + 0.25 * bassPulse - 0.12 * highPulse);
		vec3 forward = normalize(lookAt - ro);
		vec3 right = normalize(vec3(forward.z, 0.0, -forward.x));
	right.xy *= rot2(pathLook.x / 64.0 + camera_pan);
		right.xy *= rot2(-0.7 * cos(TIME * 0.12) + 0.2 * beatPulse);
		vec3 up = cross(forward, right);
	
	// Apply fisheye lens distortion
	vec2 uv_distorted = u;
	if (fisheye_strength > 0.0) {
		float r = length(u);
		float theta = atan(u.y, u.x);
		float r_distorted = r * (1.0 + fisheye_strength * r * r);
		uv_distorted = r_distorted * vec2(cos(theta), sin(theta));
	}
	
	vec3 rd = normalize(forward + FOV * uv_distorted.x * right + FOV * uv_distorted.y * up);
		vec3 lp = vec3(0.5 * FAR, FAR, 1.5 * FAR) + vec3(0.0, 0.0, ro.z);
		gRO = ro + vec3(0.0, 0.0, 1.0);
		gRO.xy = path(gRO.z);
		vec3 p2 = vec3(path(gRO.z + 1.0), gRO.z + 1.0);
		forward = normalize(p2 - gRO);
		right = normalize(vec3(forward.z, 0.0, -forward.x));
		right.xy *= rot2(pathLook.x / 32.0 + 0.1 * bassPulse);
		up = cross(forward, right);
		gbaseShip = mat3(forward, up, right);
		float dist = mix(35.0, 15.0, smoothstep(7000.0, 8500.0, gRO.z));
		dist = mix(dist, 45.0, smoothstep(10000.0, 12000.0, gRO.z));
		dist = mix(dist, dist * 1.4, audioDrive * 0.25);
		dist *= mix(1.0, 0.75, clamp(levelPulse, 0.0, 1.0));
		ro += (dist * (0.5 + 0.5 * cos(0.31 * TIME)) + 2.0) * vec3(0.3, 1.0 + 0.3 * bassPulse, -2.0);
		ro += vec3(0.0, beatPulse * 2.0, 0.0);
		ro.x += 0.3 * dist * cos(0.31 * TIME + audioDrive) + spectrumSweep * 6.0 * bassPulse;
		float t = logBisectTrace(ro, rd);
		ed = gedge;
		ed2 = gedge2;
		lastt1 = glastt;
		vec3 sky = getSky(ro, rd, normalize(lp - ro));
		col = sky;
		vec2 mapCol = mapColor(ro + t * rd);
		vec3 sp;
		float cur = 0.0;
		if (t < FAR)
		{
			sp = ro + t * rd;
			vec3 sn = normal(sp);
			vec3 ld = lp - sp;
			ld /= max(length(ld), 0.001);
			float shd = softShadow(sp, ld, 0.1, FAR, 8.0);
			cur = curve(sp);
			float ao = 1.0;
			float dif = max(dot(ld, sn), 0.0);
			float spe = pow(max(dot(reflect(-ld, sn), -rd), 0.0), 5.0);
			float fre = clamp(1.0 + dot(rd, sn), 0.0, 1.0);
			float schlick = pow(1.0 - max(dot(rd, normalize(rd + ld)), 0.0), 5.0);
			float fre2 = mix(0.2, 1.0, schlick);
			float amb = fre * fre2 + 0.06 * ao;
			col = clamp(mix(vec3(0.8, 0.5, 0.3), vec3(0.5, 0.25, 0.125), (sp.y + 1.0) * 0.15), vec3(0.5, 0.25, 0.125), vec3(1.0));
			col = pow(col, vec3(1.5));
			col = (col * (dif + 0.1) + fre2 * spe) * shd * ao + amb * col;
			vec3 audioTint = vec3(1.0 + 0.6 * bassPulse, 1.0 + 0.35 * midPulse, 1.0 + 0.25 * highPulse);
			col *= audioTint;
			col += 0.25 * highPulse * vec3(0.2, 0.4, 0.8) * smoothstep(0.0, 0.5, cur);
			vec3 stylized = 0.5 + 0.5 * cos(vec3(0.8, 0.6, 0.4) * (sp.y * 0.2 + toneShift * 6.0));
			col = mix(col, stylized, 0.35 + 0.4 * toneShift + audioDrive * 0.2);
		}
		col = pow(max(col, 0.0), vec3(0.75));
		vec3 cGround = vec3(248.0, 210.0, 155.0) / 256.0;
		vec3 cSky = vec3(177.0, 186.0, 213.0) / 256.0;
		if (t < FAR)
		{
			vec3 cFill;
			vec3 spCol = ro + t * rd;
			if (mapCol.y == ID_PATH)
			{
				cFill = mix(vec3(1.0, 0.01, 0.01), vec3(1.0, 0.4, 0.1), audioDrive);
			}
			else if (mapCol.y == ID_SHIP)
			{
				vec3 pShip = (spCol - gRO) * gbaseShip;
				cFill = mix(vec3(0.0, 1.0, 1.0), vec3(0.7), smoothstep(0.0, 0.1, pShip.x - 1.3));
				cFill = mix(cFill, vec3(0.1, 0.8, 0.3), audioDrive * 0.5);
			}
			else
			{
				cFill = mix(cGround, vec3(248.0, 185.0, 155.0) / 256.0, smoothstep(0.0, 0.1, spCol.y - 8.0));
				cFill = mix(cFill, vec3(1.0, 0.0, 0.0), 0.4 * smoothstep(1000.0, 3000.0, gRO.z));
				vec3 col3 = cos(spCol.y * 0.08 + 1.1) * clamp(mix(vec3(0.8, 0.5, 0.3), vec3(0.5, 0.25, 0.125), (spCol.y + 1.0) * 0.15), vec3(0.5, 0.25, 0.125), vec3(1.0));
				cFill = mix(cFill, col3, 0.5 * smoothstep(6000.0, 8500.0, gRO.z));
				if (media_blend > 0.0)
				{
					vec2 mediaUV = spCol.xz * 0.01 * media_scale + TIME * 0.02;
					vec3 mediaSample = texture(syn_Media, mediaUV).rgb;
					cFill = mix(cFill, mediaSample, media_blend * 0.7);
				}
			}
			vec3 audioInk = mix(vec3(0.95, 0.5, 0.2), vec3(0.25, 0.65, 1.1), clamp(highPulse, 0.0, 1.0));
			cFill = mix(cFill, audioInk, clamp(0.4 * bassPulse + 0.3 * spectrumSweep, 0.0, 0.8));
			col = mix(cFill, cSky, t / FAR) * (0.5 + 0.5 * smoothstep(0.4, 0.5, length(col) + audioDrive * 0.3));
			col = mix(col, vec3(0.0), ed);
			col = mix(vec3(0.0), col, 0.5 + 0.5 * smoothstep(0.4, 0.41, cur));
			ed2 += cur < 0.35 ? 1.0 : 0.0;
		}
		else
		{
			col = mix(cSky * abs(1.0 - rd.y), vec3(1.0), smoothstep(1.3, 1.4, length(col)));
			col = mix(col, vec3(0.1), ed);
			float sun = max(dot(rd, normalize(lp - ro)), 0.0);
			col = mix(vec3(0.0), col, smoothstep(0.09 / resolution.y, 0.2 / resolution.y, abs(sun - 0.9892)));
		}
		col = mix(col, cSky * abs(1.0 - rd.y), sqrt(smoothstep(FAR - (ed < 0.0 ? 200.0 : 100.0), FAR, lastt1)));
	}
	col = mix(col, col * (1.0 + vec3(0.6, 0.3, 0.1) * bassPulse), 0.5);
	col = mix(col, vec3(1.0), clamp(0.2 * highPulse + 0.3 * beatPulse, 0.0, 0.4));
	col = mix(col, vec3(0.2), smoothstep(0.0, 1.0 / resolution.y, dBox));
	col = mix(col, vec3(0.0), smoothstep(1.0 / resolution.y, 0.0, abs(dBox) - 0.005));
	float edgeOut = clamp(ed2 * 0.25, 0.0, 1.0);
	return vec4(clamp(col, 0.0, 1.0), edgeOut);
}

vec4 renderMain(void)
{
	if (PASSINDEX == 0)
	{
		return renderScene(_xy, RENDERSIZE.xy);
	}
	vec4 base = texture(cartoon_buffer, _uv);
	vec2 bufPx = 1.0 / CARTOON_BUFFER_RES;
	vec3 blur = (texture(cartoon_buffer, _uv + vec2(bufPx.x, 0.0)).rgb +
		        texture(cartoon_buffer, _uv - vec2(bufPx.x, 0.0)).rgb +
		        texture(cartoon_buffer, _uv + vec2(0.0, bufPx.y)).rgb +
		        texture(cartoon_buffer, _uv - vec2(0.0, bufPx.y)).rgb) * 0.25;
	float edgeMask = smoothstep(0.2, 0.9, base.a);
	vec3 color = mix(base.rgb, blur, edgeMask * 0.65);

	float bassPulse = audio_reactivity * bass_emphasis * clamp(syn_BassHits * 1.3 + syn_BassLevel, 0.0, 2.5);
	float midPulse = audio_reactivity * clamp(syn_MidHits * 1.0 + syn_MidLevel, 0.0, 2.5);
	float highPulse = audio_reactivity * high_emphasis * clamp(syn_HighHits * 1.2 + syn_HighLevel, 0.0, 2.5);
	float spectrumSweep = texture(syn_Spectrum, fract(_uv.x + TIME * 0.07)).g;
	float trailBass = texture(syn_LevelTrail, _uv.x).g;

	vec3 bassGlow = vec3(0.95, 0.45, 0.15) * bassPulse;
	vec3 rimFlash = vec3(0.25, 0.6, 1.2) * highPulse;
	color += bassGlow * (0.3 + 0.7 * edgeMask);
	color += rimFlash * edgeMask * smoothstep(0.3, 1.0, spectrumSweep);

	float scanline = 1.0 + scanline_intensity * audio_reactivity * sin(((_uv.y * RENDERSIZE.y) * 0.35 + TIME * 18.0) + syn_BPMTwitcher * 6.2831);
	color *= scanline;

	float contrastBump = 1.0 + 0.4 * midPulse;
	color = pow(color, vec3(1.0 / (1.2 + 0.4 * spectrumSweep)));
	color = mix(color, vec3(1.0), clamp(0.3 * syn_OnBeat * audio_reactivity + 0.4 * trailBass, 0.0, 0.7));
	color = clamp(color * contrastBump, 0.0, 1.0);
	return vec4(color, 1.0);
}
