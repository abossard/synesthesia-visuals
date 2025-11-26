// === ARCADE PIXEL SHADER ===
// Retro C64/Synthwave style with beat reactivity + pixelated media + gloss effects

vec4 backgroundColor = vec4(backgroundColor_color, 1.0);
vec3 borderColor = borderColor_color;
bool useBackgroundColor = (useBackgroundColor_bool > 0.5);
bool beatReactive = (beatReactive_bool > 0.5);
bool showMedia = (showMedia_bool > 0.5);

// === SIMPLEX NOISE (simplified for blocky look) ===
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod289(i);
    vec4 p = permute(permute(permute(
                i.z + vec4(0.0, i1.z, i2.z, 1.0))
                + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// === 4x4 BAYER DITHER MATRIX (C64 style) ===
float bayerDither(vec2 pos) {
    int x = int(mod(pos.x, 4.0));
    int y = int(mod(pos.y, 4.0));
    int index = x + y * 4;
    // Classic 4x4 Bayer matrix
    float bayer[16];
    bayer[0] = 0.0/16.0;  bayer[1] = 8.0/16.0;  bayer[2] = 2.0/16.0;  bayer[3] = 10.0/16.0;
    bayer[4] = 12.0/16.0; bayer[5] = 4.0/16.0;  bayer[6] = 14.0/16.0; bayer[7] = 6.0/16.0;
    bayer[8] = 3.0/16.0;  bayer[9] = 11.0/16.0; bayer[10] = 1.0/16.0; bayer[11] = 9.0/16.0;
    bayer[12] = 15.0/16.0; bayer[13] = 7.0/16.0; bayer[14] = 13.0/16.0; bayer[15] = 5.0/16.0;
    return bayer[index];
}

// === SYNTHWAVE NEON PALETTE ===
vec3 getSynthwaveColor(float t) {
    // Hot pink → Electric blue → Cyan → Purple cycle
    vec3 colors[5];
    colors[0] = vec3(0.05, 0.0, 0.1);   // Deep purple/black
    colors[1] = vec3(1.0, 0.0, 0.5);    // Hot pink
    colors[2] = vec3(0.0, 0.8, 1.0);    // Cyan
    colors[3] = vec3(0.5, 0.0, 1.0);    // Purple
    colors[4] = vec3(1.0, 0.2, 0.8);    // Magenta
    
    t = clamp(t, 0.0, 1.0);
    float idx = t * 4.0;
    int i0 = int(floor(idx));
    int i1 = min(i0 + 1, 4);
    float fract_t = fract(idx);
    return mix(colors[i0], colors[i1], fract_t);
}

// === 8-BIT PASTEL PALETTE ===
vec3 getPastelColor(float t) {
    // Soft pastels like C64/NES
    vec3 colors[5];
    colors[0] = vec3(0.2, 0.2, 0.3);    // Muted dark blue
    colors[1] = vec3(0.6, 0.8, 0.9);    // Sky blue
    colors[2] = vec3(0.9, 0.7, 0.8);    // Pink
    colors[3] = vec3(0.7, 0.9, 0.7);    // Mint green
    colors[4] = vec3(1.0, 0.9, 0.7);    // Cream/peach
    
    t = clamp(t, 0.0, 1.0);
    float idx = t * 4.0;
    int i0 = int(floor(idx));
    int i1 = min(i0 + 1, 4);
    float fract_t = fract(idx);
    return mix(colors[i0], colors[i1], fract_t);
}

// === QUANTIZE TO PALETTE ===
float quantize(float value, float steps) {
    return floor(value * steps + 0.5) / steps;
}

vec3 getBlendedPaletteColor(float t, float theme) {
    vec3 synthwave = getSynthwaveColor(t);
    vec3 pastel = getPastelColor(t);
    return mix(synthwave, pastel, theme);
}

// === GLOSS/SPARKLE EFFECTS ===

// 1. Diagonal sweep - single bright line moving diagonally
float glossDiagonalEffect(vec2 uv, float time, float beatBoost) {
    float diag = (uv.x + uv.y) * 0.5; // normalize to 0-1 range
    float sweep = fract(diag - time * glossSpeed + beatBoost * 0.2);
    float highlight = smoothstep(glossWidth, 0.0, abs(sweep - 0.5) * 2.0);
    return highlight * glossDiagonal;
}

// 2. Parallel bands - multiple diagonal stripes
float glossParallelEffect(vec2 uv, float time, float beatBoost) {
    float diag = (uv.x + uv.y) * 3.0; // more repetitions
    float bands = fract(diag - time * glossSpeed * 0.7);
    float highlight = smoothstep(glossWidth * 0.5, 0.0, abs(bands - 0.5) * 2.0);
    // Add second set of bands offset
    float bands2 = fract(diag * 0.6 - time * glossSpeed * 0.5 + 0.3);
    float highlight2 = smoothstep(glossWidth * 0.3, 0.0, abs(bands2 - 0.5) * 2.0);
    return (highlight * 0.7 + highlight2 * 0.3) * glossParallel * (1.0 + beatBoost * 0.5);
}

// 3. Radial pulse - expanding ring from center
float glossRadialEffect(vec2 uv, float time, float beatBoost) {
    vec2 center = uv - 0.5;
    float dist = length(center);
    // Pulse expands outward, triggered more on beat
    float pulse = fract(dist * 2.0 - time * glossSpeed - beatBoost * 0.3);
    float ring = smoothstep(glossWidth, 0.0, abs(pulse - 0.5) * 2.0);
    // Fade out at edges
    ring *= smoothstep(0.7, 0.3, dist);
    return ring * glossRadial * (1.0 + beatBoost);
}

// === 2D ROTATION HELPER ===
vec2 rotate2D(vec2 uv, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

// === PIXELATED MEDIA SAMPLING ===
vec4 samplePixelatedMedia(vec2 uv, float pixelSize) {
    // Center UV around 0.5 for proper rotation/scale
    vec2 centered = uv - 0.5;
    
    // Apply scale (inverse - smaller scale value = zoom in)
    centered /= mediaScale;
    
    // Apply rotation (convert degrees to radians)
    float angle = mediaRotation * 3.14159265 / 180.0;
    centered = rotate2D(centered, angle);
    
    // Move back from center
    vec2 transformedUV = centered + 0.5;
    
    // Pixelate the UV coordinates
    vec2 gridRes = RENDERSIZE.xy / pixelSize;
    vec2 pixelatedUV = floor(transformedUV * gridRes) / gridRes + 0.5 / gridRes;
    
    // Sample media with aspect correction using pixelated UVs
    // _textureMedia handles aspect ratio internally
    vec4 mediaColor = _textureMedia(pixelatedUV);
    
    // Quantize media colors for extra retro look
    float steps = max(paletteSize, 2.0);
    mediaColor.rgb = floor(mediaColor.rgb * steps + 0.5) / steps;
    
    return mediaColor;
}

vec4 renderMain() {
    vec4 out_FragColor = vec4(0.0);
    vec2 pix = _xy.xy;
    vec2 uv = _uv;
    
    // === BEAT REACTIVITY ===
    float beatPulse = 0.0;
    float colorFlash = 0.0;
    float glossBeatBoost = 0.0;
    if (beatReactive) {
        beatPulse = syn_BassLevel * beatPulseStrength * 8.0;
        colorFlash = syn_HighHits * 0.3;
        glossBeatBoost = syn_BassHits * 2.0 + syn_OnBeat * 0.5;
    }
    
    // Grid size with beat pulse
    float gs = max(gridSize + beatPulse, 4.0);
    vec2 cell = floor(pix / gs);
    vec2 within = mod(pix, gs);
    float gap = spacing;
    float border = borderWidth;
    
    // Base background
    if (useBackgroundColor) {
        out_FragColor = backgroundColor;
    } else {
        out_FragColor = vec4(0.0);
    }
    
    // === SCANLINES ===
    float scanline = 1.0 - scanlineStrength * 0.5 * (1.0 - mod(pix.y, 2.0));
    
    // === MEDIA LAYER (rendered first as base) ===
    vec4 mediaLayer = vec4(0.0);
    if (showMedia) {
        mediaLayer = samplePixelatedMedia(uv, mediaPixelSize);
        mediaLayer.a *= mediaOpacity;
        
        // Compute gloss effects for media
        float totalGloss = 0.0;
        totalGloss += glossDiagonalEffect(uv, TIME, glossBeatBoost);
        totalGloss += glossParallelEffect(uv, TIME, glossBeatBoost);
        totalGloss += glossRadialEffect(uv, TIME, glossBeatBoost);
        
        // Apply gloss as additive white highlight
        vec3 glossColor = vec3(1.0, 0.95, 0.9); // Warm white
        mediaLayer.rgb += glossColor * totalGloss * mediaLayer.a;
        mediaLayer.rgb *= scanline;
    }
    
    // === PIXEL RENDERING ===
    bool inGap = within.x < gap || within.x > gs - gap || 
                 within.y < gap || within.y > gs - gap;
    bool inBorder = !inGap && (
                    within.x < gap + border || within.x > gs - gap - border ||
                    within.y < gap + border || within.y > gs - gap - border);
    bool inCell = !inGap && !inBorder;
    
    // Start with media as base (Option B: additive blend)
    if (showMedia && mediaLayer.a > 0.0) {
        out_FragColor.rgb = mix(out_FragColor.rgb, mediaLayer.rgb, mediaLayer.a);
        out_FragColor.a = max(out_FragColor.a, mediaLayer.a);
    }
    
    if (inBorder) {
        // Hard pixel border
        vec3 bc = borderColor;
        // Brighten border on beat
        if (beatReactive) {
            bc += vec3(syn_OnBeat * 0.3);
        }
        out_FragColor = vec4(bc * scanline, 1.0);
    }
    else if (inCell) {
        // Sample noise at cell center for uniform block color
        vec2 cellUV = (cell * gs + gs * 0.5) / RENDERSIZE.xy;
        
        // Simple 2-octave noise for blocky look
        vec3 p = vec3(
            cellUV.x / zoom * horizontalScale, 
            cellUV.y / zoom * verticalScale, 
            TIME * speed
        );
        float noiseValue = snoise(p) * 0.7 + snoise(p * 2.0) * 0.3;
        
        // Normalize to 0-1
        float intensity = (noiseValue + 1.0) * 0.5;
        
        // === C64 DITHERING ===
        float dither = bayerDither(cell) - 0.5;
        intensity += dither * ditherStrength * 0.2;
        
        // === QUANTIZE TO PALETTE STEPS ===
        float steps = max(paletteSize, 2.0);
        intensity = quantize(intensity, steps);
        
        // Add beat flash
        intensity = clamp(intensity + colorFlash, 0.0, 1.0);
        
        // Get color from blended palette
        vec3 noiseColor = getBlendedPaletteColor(intensity, colorTheme);
        
        // Apply scanline
        noiseColor *= scanline;
        
        // Additive blend with media layer (Option B)
        if (showMedia && mediaLayer.a > 0.0) {
            // Additive blend: noise adds color to media
            vec3 blended = out_FragColor.rgb + noiseColor * 0.5;
            out_FragColor = vec4(blended, maxOpacity);
        } else {
            out_FragColor = vec4(noiseColor, maxOpacity);
        }
    }
    
    return out_FragColor;
}
