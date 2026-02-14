// MoriaGears Storyforge
// Inspired by BWmoria_gears / srtuss Industry structure, rebuilt for Synesthesia SSF.

float hash1(float x)
{
    return fract(sin(x) * 43758.5453123);
}

vec2 hash2(vec2 p)
{
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

vec2 rotate2(vec2 p, float a)
{
    float c = cos(a);
    float s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float mechstep(float x, float f, float r)
{
    float fr = fract(x);
    float fl = floor(x);
    return fl + pow(fr, 0.5) + sin(fr * f) * exp(-fr * 3.5) * r;
}

vec3 voronoiId(vec2 x)
{
    vec2 n = floor(x);
    vec2 f = fract(x);
    vec2 mg = vec2(0.0);
    vec2 mr = vec2(0.0);
    float md = 8.0;

    for (int j = -1; j <= 1; ++j)
    {
        for (int i = -1; i <= 1; ++i)
        {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash2(n + g);
            vec2 r = g + o - f;
            float d = max(abs(r.x), abs(r.y));
            if (d < md)
            {
                md = d;
                mr = r;
                mg = g;
            }
        }
    }

    return vec3(n + mg, mr);
}

float maskFromSdf(float d)
{
    return 1.0 - step(0.0, d);
}

float gearMask(vec2 p, vec2 at, float teeth, float size, float ang)
{
    p -= at;
    float le = length(p);
    float body = le - 0.30 * size;

    float tw = sin(atan(p.y, p.x) * teeth + ang);
    float tooth = smoothstep(-0.7, 0.7, tw) * (0.11 * size);

    float d = min(body, body - tooth);
    d = max(d, -(le - 0.055 * size));

    return maskFromSdf(d);
}

float fanMask(vec2 p, vec2 at, float ang)
{
    p = (p - at) * 3.0;
    float le = length(p);
    float d = le - 1.0;
    if (d > 0.0)
    {
        return 0.0;
    }

    float a = sin(atan(p.y, p.x) * 3.0 + ang);
    float d1 = -(le - 0.05 + a * 0.8);
    float d2 = -(le - 0.15);
    d = max(d, d1);
    d = max(d, d2);

    return maskFromSdf(d);
}

float cartMask(vec2 p, vec2 at)
{
    p -= at;
    float dWheelA = length(p + vec2(-0.06, -0.31)) - 0.035;
    float dWheelB = length(p + vec2(0.06, -0.31)) - 0.035;
    vec2 box = abs(p + vec2(0.0, -0.39));
    float dBody = max(box.x - 0.11, box.y - 0.06);
    float d = min(min(dWheelA, dWheelB), dBody);
    return maskFromSdf(d);
}

float waveMask(vec2 p, float phase)
{
    float y = sin(p.x * 1.8 + phase) * 0.18 + sin(p.x * 4.7 - phase * 1.3) * 0.06;
    float d = abs(p.y - y) - 0.045;
    return maskFromSdf(d);
}

float vineMask(vec2 p, float phase)
{
    float x = sin(p.y * 1.7 + phase) * 0.45 + sin(p.y * 3.1 - phase * 0.6) * 0.18;
    float d = abs(p.x - x) - 0.05;
    return maskFromSdf(d);
}

float leafMask(vec2 p, float phase)
{
    vec2 q = p;
    q.x = mod(q.x + 0.65, 1.3) - 0.65;
    q = rotate2(q, sin(phase + floor((p.x + 20.0) * 0.7)) * 0.25);
    float d = length(q / vec2(0.23, 0.09)) - 1.0;
    return maskFromSdf(d);
}

float ringMask(vec2 p, vec2 at, float radius, float width)
{
    float d = abs(length(p - at) - radius) - width;
    return maskFromSdf(d);
}

float boxSdf2(vec2 p, vec2 b)
{
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sharkMask(vec2 p, vec2 at, float phase, float mirrorDir)
{
    vec2 q = p - at;
    q.x *= sign(mirrorDir);
    q = rotate2(q, 0.07 * sin(phase));

    float body = length(q / vec2(0.42, 0.14)) - 1.0;
    float tailA = boxSdf2(q + vec2(0.43, 0.06), vec2(0.10, 0.025));
    float tailB = boxSdf2(q + vec2(0.43, -0.06), vec2(0.10, 0.025));
    float fin = boxSdf2(rotate2(q + vec2(-0.02, 0.14), 0.6), vec2(0.12, 0.03));
    float dorsal = boxSdf2(rotate2(q + vec2(0.10, 0.18), -0.35), vec2(0.08, 0.025));

    float shark = min(min(body, tailA), min(tailB, min(fin, dorsal)));

    float mouthCut = boxSdf2(rotate2(q + vec2(-0.28, 0.03), -0.28), vec2(0.12, 0.03));
    shark = max(shark, -mouthCut);

    float teeth = 0.0;
    for (int i = 0; i < 4; ++i)
    {
        float fi = float(i);
        vec2 tp = q + vec2(-0.17 - fi * 0.055, 0.045 + 0.006 * sin(phase + fi));
        float tooth = boxSdf2(rotate2(tp, -0.78), vec2(0.02, 0.007));
        teeth = max(teeth, maskFromSdf(tooth));
    }

    return max(maskFromSdf(shark), teeth * 0.9);
}

float dwarfMask(vec2 p, vec2 at, float phase)
{
    vec2 q = p - at;
    q = rotate2(q, 0.04 * sin(phase * 0.7));

    float head = length(q / vec2(0.18, 0.16)) - 1.0;
    float helmet = boxSdf2(q + vec2(0.0, 0.17), vec2(0.21, 0.07));
    float beard = length((q + vec2(0.0, -0.14)) / vec2(0.15, 0.20)) - 1.0;
    float hornL = boxSdf2(rotate2(q + vec2(0.20, 0.22), 0.55), vec2(0.07, 0.02));
    float hornR = boxSdf2(rotate2(q + vec2(-0.20, 0.22), -0.55), vec2(0.07, 0.02));

    float dwarf = min(min(head, helmet), min(beard, min(hornL, hornR)));

    float eyeL = boxSdf2(q + vec2(0.06, 0.02), vec2(0.022, 0.010));
    float eyeR = boxSdf2(q + vec2(-0.06, 0.02), vec2(0.022, 0.010));
    dwarf = max(dwarf, -eyeL);
    dwarf = max(dwarf, -eyeR);

    float grin = boxSdf2(rotate2(q + vec2(0.0, -0.06), 0.12 * sin(phase * 0.4)), vec2(0.10, 0.02));
    dwarf = max(dwarf, -grin);

    float teeth = 0.0;
    for (int i = 0; i < 5; ++i)
    {
        float fi = float(i);
        vec2 tp = q + vec2(-0.08 + fi * 0.04, -0.055);
        float tooth = boxSdf2(tp, vec2(0.009, 0.010));
        teeth = max(teeth, maskFromSdf(tooth));
    }

    return max(maskFromSdf(dwarf), teeth * 0.95);
}

float pumaMask(vec2 p, vec2 at, float phase)
{
    vec2 q = p - at;
    q = rotate2(q, 0.05 * sin(phase * 0.8));

    float skull = length(q / vec2(0.22, 0.16)) - 1.0;
    float jaw = boxSdf2(q + vec2(0.0, -0.14), vec2(0.15, 0.05));
    float earL = length((q + vec2(0.14, 0.16)) / vec2(0.06, 0.07)) - 1.0;
    float earR = length((q + vec2(-0.14, 0.16)) / vec2(0.06, 0.07)) - 1.0;
    float nose = boxSdf2(q + vec2(0.0, -0.01), vec2(0.035, 0.02));

    float puma = min(min(skull, jaw), min(earL, min(earR, nose)));

    float eyeL = boxSdf2(rotate2(q + vec2(0.075, 0.03), -0.28), vec2(0.028, 0.008));
    float eyeR = boxSdf2(rotate2(q + vec2(-0.075, 0.03), 0.28), vec2(0.028, 0.008));
    puma = max(puma, -eyeL);
    puma = max(puma, -eyeR);

    float mouth = boxSdf2(q + vec2(0.0, -0.09), vec2(0.08, 0.014));
    puma = max(puma, -mouth);

    float fangs = 0.0;
    for (int i = 0; i < 4; ++i)
    {
        float fi = float(i);
        float side = fi < 2.0 ? -1.0 : 1.0;
        float idx = mod(fi, 2.0);
        vec2 fp = q + vec2(side * (0.03 + idx * 0.03), -0.11 - idx * 0.012);
        float fang = boxSdf2(rotate2(fp, side * 0.55), vec2(0.018, 0.006));
        fangs = max(fangs, maskFromSdf(fang));
    }

    return max(maskFromSdf(puma), fangs);
}

float starMask(vec2 p, float phase, float layerId)
{
    vec2 cell = floor((p + vec2(0.0, phase * 0.6)) * 5.0);
    float rnd = hash1(dot(cell, vec2(41.0, 289.0)) + layerId * 17.0);
    vec2 f = fract(p * 5.0) - 0.5;
    float d = length(f) - (0.035 + 0.02 * hash1(rnd * 19.0));
    return maskFromSdf(d) * step(0.985, rnd);
}

float psychMask(vec2 p, float phase)
{
    vec2 q = p + 0.25 * vec2(sin(p.y * 5.0 + phase * 1.6), cos(p.x * 5.5 - phase * 1.2));
    float bands = 0.5 + 0.5 * sin(q.x * 12.0 + sin(q.y * 6.0 + phase * 2.0) * 2.5);
    float blobs = 0.5 + 0.5 * sin((q.x * q.y) * 16.0 - phase * 3.0);
    return smoothstep(0.62, 0.95, mix(bands, blobs, 0.45));
}

float layerMask(
    vec2 p,
    float layerId,
    float wMarine,
    float wMoria,
    float wJungle,
    float wSpace,
    float wPsych,
    float t,
    float pulse,
    float detail
)
{
    float si = floor(p.y / 3.0) * 3.0;
    float sr = hash1(si + layerId * 127.13);

    vec2 sp = vec2(p.x, mod(p.y, 3.0) - 1.5);
    sp.y -= sr * 0.6;

    float st = t + sr * 3.7;
    float strut = step(abs(sp.y + 0.2), 0.11) + step(abs(sp.y - 0.3), 0.08);

    float cell = step(1.6 + detail * 0.4, abs(voronoiId(p * 0.92 + vec2(0.31, layerId * 19.1)).x) + strut * 0.3);
    float holeL = maskFromSdf(length(sp - vec2(-2.2, 0.5)) - 0.18);
    float holeR = maskFromSdf(length(sp - vec2(2.2, 0.5)) - 0.18);
    float wall = clamp(cell - 0.6 * holeL - 0.6 * holeR, 0.0, 1.0);

    float ang = mix(st * (sr - 0.5) * 26.0, mechstep(st * 2.0, 20.0, 0.45) * 3.1, 0.7);

    float machine = 0.0;
    machine = max(machine, gearMask(sp, vec2(-1.65 + 3.3 * sr, 0.35), 8.0, 1.0, ang));
    machine = max(machine, gearMask(sp, vec2(-1.0 + 3.3 * sr, 0.25), 7.0, 0.82, -ang));
    machine = max(machine, gearMask(sp, vec2(-2.15 + 3.3 * sr, 0.22), 5.0, 0.55, -ang + 0.7));
    machine = max(machine, fanMask(sp, vec2(2.0, 0.55), ang * 42.0));
    machine = max(machine, cartMask(sp, vec2(mod(st * mix(1.4, 2.2, sr), 4.5) - 2.25, -0.08)));

    float marine = 0.0;
    marine = max(marine, waveMask(sp, st * 1.2));
    marine = max(marine, waveMask(sp + vec2(0.0, 0.25), -st * 0.9));
    marine = max(marine, fanMask(sp, vec2(-1.9, 0.4), -ang * 20.0));
    marine = max(marine, ringMask(sp, vec2(1.7 * sin(st * 0.6 + sr * 8.0), 0.15), 0.09, 0.03));
    marine = max(marine, sharkMask(sp, vec2(-1.45 + mod(st * 0.55 + sr * 2.0, 2.9), -0.15 + 0.25 * sin(st * 0.35)), st, 1.0));
    marine = max(marine, sharkMask(sp, vec2(1.45 - mod(st * 0.47 + sr * 2.8, 2.9), 0.20 + 0.18 * cos(st * 0.28)), st + 1.7, -1.0));

    float jungle = 0.0;
    jungle = max(jungle, vineMask(sp, st * 0.85 + sr * 4.0));
    jungle = max(jungle, leafMask(sp + vec2(0.0, 0.1 * sin(st + sr * 8.0)), st));
    jungle = max(jungle, leafMask(rotate2(sp, 0.4), -st * 0.7));
    jungle = max(jungle, pumaMask(sp, vec2(-1.2 + mod(st * 0.38 + sr * 3.0, 2.4), -0.20 + 0.08 * sin(st * 0.45)), st));
    jungle = max(jungle, pumaMask(sp, vec2(1.2 - mod(st * 0.34 + sr * 2.4, 2.4), 0.02 + 0.06 * cos(st * 0.33)), st + 1.9));

    float space = 0.0;
    space = max(space, starMask(sp * 0.75, st, layerId));
    space = max(space, ringMask(sp, vec2(0.0, 0.35 + 0.25 * sin(st * 0.7 + sr * 4.0)), 0.65, 0.03));
    space = max(space, ringMask(sp, vec2(0.0, 0.35 + 0.25 * sin(st * 0.7 + sr * 4.0)), 0.45, 0.02));

    float psych = 0.0;
    psych = max(psych, psychMask(sp * 0.9, st));
    psych = max(psych, psychMask(rotate2(sp, 0.6), -st * 1.15) * 0.75);

    machine = max(machine, dwarfMask(sp, vec2(-1.35 + 2.7 * sr, -0.08), st));
    machine = max(machine, dwarfMask(sp, vec2(-0.65 + 2.7 * sr, 0.02), st + 1.4));

    float motifBlend = machine * wMoria
        + marine * wMarine
        + jungle * wJungle
        + space * wSpace
        + psych * wPsych;

    float motif = smoothstep(0.28, 0.72, motifBlend);

    float wallBias = 0.45 + 0.35 * wMoria + 0.2 * wJungle + 0.15 * wMarine + 0.1 * wSpace + 0.2 * wPsych;
    float layer = max(motif, wall * wallBias);

    float burst = pulse * (0.08 + 0.12 * wPsych) * step(0.92, hash1(sr * 91.7 + layerId));
    layer = clamp(layer + burst, 0.0, 1.0);

    return layer;
}

vec4 renderMain(void)
{
    vec2 uv = _uv * 2.0 - 1.0;
    vec2 p = uv;
    p.x *= RENDERSIZE.x / RENDERSIZE.y;

    float bass = clamp(syn_BassLevel * bass_emphasis, 0.0, 1.5);
    float highs = clamp(syn_HighLevel * high_emphasis, 0.0, 1.5);
    float energy = clamp(story_energy, 0.0, 2.0);
    float scriptActivity = clamp(story_activity, 0.0, 1.0);
    float rawSignal = max(
        max(syn_Intensity * 0.9, syn_Presence * 0.75),
        max(max(syn_BassLevel * 0.8, syn_HighLevel * 0.7), max(syn_BassHits * 0.8, syn_HighHits * 0.7))
    );
    float signalActivity = smoothstep(0.14, 0.52, rawSignal);
    float audioGate = clamp(max(signalActivity, scriptActivity), 0.0, 1.0);
    float damp = clamp(story_damp, 0.03, 1.0);
    float motionGate = audioGate * audioGate;
    float pulse = clamp(max(story_pulse, syn_BassHits * 0.55 + syn_HighHits * 0.35), 0.0, 1.2)
        * audio_reactivity * damp * motionGate;

    float audioDrive = 1.0 + (0.20 * syn_Presence + 0.18 * energy + 0.08 * bass) * damp * audioGate;
    audioDrive = clamp(audioDrive, 0.85, 1.25);
    float drive = mix(1.0, audioDrive, audio_reactivity);
    float safeMasterSpeed = clamp(master_speed, 0.02, 0.85);
    float t = TIME * safeMasterSpeed * 0.45 * drive * motionGate;

    float themePosManual = clamp(theme_mode, 0.0, 4.0);
    float themePosAuto = mix(story_theme_a, story_theme_b, clamp(story_theme_blend, 0.0, 1.0));
    float themePos = mix(themePosManual, themePosAuto, step(0.5, story_auto));

    float wMarine = max(1.0 - abs(themePos - 0.0), 0.0);
    float wMoria = max(1.0 - abs(themePos - 1.0), 0.0);
    float wJungle = max(1.0 - abs(themePos - 2.0), 0.0);
    float wSpace = max(1.0 - abs(themePos - 3.0), 0.0);
    float wPsych = max(1.0 - abs(themePos - 4.0), 0.0);

    float wSum = max(wMarine + wMoria + wJungle + wSpace + wPsych, 1e-4);
    wMarine /= wSum;
    wMoria /= wSum;
    wJungle /= wSum;
    wSpace /= wSum;
    wPsych /= wSum;

    float zoom = 1.0 + camera_zoom * (0.1 + 0.9 * audio_reactivity * syn_Presence * audioGate);
    p *= zoom;

    float sway = camera_sway * audio_reactivity * motionGate;
    vec2 cam = vec2(
        sin(t * 0.45) * sway,
        t * (0.07 + (0.26 + 0.07 * bass) * motionGate)
    );

    float camRot = 0.005 * sin(t * 0.4) + glitch_amount * pulse * 0.03;
    p = rotate2(p, camRot);

    const int MAX_LAYERS = 8;
    float layers = clamp(depth_layers, 3.0, 8.0);

    float acc = 0.0;
    float z = 3.2 - 0.15 * sin(t * 0.32);

    for (int i = 0; i < MAX_LAYERS; ++i)
    {
        if (float(i) >= layers)
        {
            continue;
        }

        float zz = 0.3 + z;
        float f = zz * 1.85 * (1.0 + 0.06 * detail_density);

        vec2 lp = p * f + cam + vec2(0.0, 0.35) * float(i);
        if (mod(float(i), 2.0) > 0.5)
        {
            lp += vec2(0.2, -0.1);
        }

        float w = layerMask(lp, float(i), wMarine, wMoria, wJungle, wSpace, wPsych, t, pulse, detail_density);
        float depthTone = exp(-abs(zz) * 0.33 + 0.12);
        acc = mix(acc, depthTone, w);

        z -= 0.58;
    }

    float mono = clamp(1.0 - acc, 0.0, 1.0);
    mono = pow(mono, mix(0.85, 1.25, mood_darkness));

    float spec = texture(syn_Spectrum, clamp(0.1 + 0.8 * _uv.x, 0.0, 1.0)).g;
    float trail = texture(syn_LevelTrail, clamp(_uv.x, 0.0, 1.0)).r;
    float reactiveLift = audio_reactivity * (0.15 * spec + 0.1 * trail + 0.25 * pulse) * damp * audioGate;
    mono = clamp(mono + reactiveLift * 0.35, 0.0, 1.0);

    vec3 darkMarine = vec3(0.02, 0.11, 0.15);
    vec3 darkMoria = vec3(0.08, 0.08, 0.09);
    vec3 darkJungle = vec3(0.04, 0.13, 0.05);
    vec3 darkSpace = vec3(0.02, 0.02, 0.08);
    vec3 darkPsych = vec3(0.07, 0.02, 0.09);

    vec3 lightMarine = vec3(0.24, 0.75, 0.86);
    vec3 lightMoria = vec3(0.86, 0.82, 0.70);
    vec3 lightJungle = vec3(0.53, 0.86, 0.38);
    vec3 lightSpace = vec3(0.76, 0.66, 1.00);
    vec3 lightPsych = vec3(1.00, 0.41, 0.83);

    vec3 accentMarine = vec3(0.55, 0.95, 1.00);
    vec3 accentMoria = vec3(1.00, 0.70, 0.35);
    vec3 accentJungle = vec3(0.90, 1.00, 0.55);
    vec3 accentSpace = vec3(1.00, 0.85, 1.00);
    vec3 accentPsych = vec3(0.50, 1.00, 0.98);

    vec3 darkColor = darkMarine * wMarine + darkMoria * wMoria + darkJungle * wJungle + darkSpace * wSpace + darkPsych * wPsych;
    vec3 lightColor = lightMarine * wMarine + lightMoria * wMoria + lightJungle * wJungle + lightSpace * wSpace + lightPsych * wPsych;
    vec3 accentColor = accentMarine * wMarine + accentMoria * wMoria + accentJungle * wJungle + accentSpace * wSpace + accentPsych * wPsych;

    vec3 col = mix(darkColor, lightColor, mono);
    col += accentColor * (0.08 + 0.25 * pulse) * (0.2 + 0.8 * (1.0 - mono));

    float psychAmount = pow(max(0.0, wPsych), 1.3) * (0.15 + 0.35 * audio_reactivity * motionGate);
    vec3 psychPalette = _palette(
        mono + t * 0.04 + pulse * 0.2,
        vec3(0.5),
        vec3(0.5),
        vec3(1.0, 0.7, 0.4),
        vec3(0.0, 0.33, 0.67)
    );
    col = mix(col, psychPalette, psychAmount);

    vec2 mediaUv = _uv + media_distortion * 0.015
        * vec2(sin(t * 1.4 + _uv.y * 18.0), cos(t * 1.2 + _uv.x * 14.0))
        * (0.3 + 0.7 * audio_reactivity * syn_Presence);
    vec4 media = _textureMedia(mediaUv);
    col = mix(col, col * (0.65 + 0.6 * media.rgb), media_blend * media.a);

    float vignette = smoothstep(1.45, 0.25, length(_uvc * (1.0 + 0.15 * camera_zoom)));
    col *= mix(0.55, 1.0, vignette);

    col *= brightness;
    col = (col - 0.5) * (1.0 + contrast * 1.8) + 0.5;
    col += pulse * audio_reactivity * (0.04 + 0.08 * highs);

    return vec4(clamp(col, 0.0, 1.0), 1.0);
}
