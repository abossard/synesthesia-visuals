// Global Wind - Atmospheric Pressure & Circulation Model
// Original by David A Roberts <https://davidar.io>
// Converted from Shadertoy to Synesthesia

// ============ COMMON ============
#define MAPRES vec2(144,72)

#define PASS1 vec2(0.0,0.0)
#define PASS2 vec2(0.0,0.5)
#define PASS3 vec2(0.5,0.0)
#define PASS4 vec2(0.5,0.5)

#define N vec2( 0, 1)
#define E vec2( 1, 0)
#define S vec2( 0,-1)
#define W vec2(-1, 0)

#define PI 3.14159265359

#define HASHSCALE1 .1031
#define HASHSCALE3 vec3(.1031, .1030, .0973)

float hash11(float p) {
    vec3 p3 = fract(vec3(p) * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash21(float p) {
    vec3 p3 = fract(vec3(p) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ============ BUFFER A: Land/Ocean Map ============
const vec2 bitmap_size = vec2(160, 72);
const int[] palette = int[] ( 0x00000000, 0x00ffffff );
const int[] rle = int[] ( 0x0001ff91, 0x03ff9100, 0xf8000000, 0x0008ff8f, 0xfffc0000, 0xf80fffff, 0x010aff89, 0xfe000000, 0x39ffffff, 0xff88fc3c, 0x0000030a, 0xffffc000, 0xc0003fff, 0x0100ff88, 0x80050084, 0x0000ffbf, 0x00ff87fe, 0x07008607, 0x20000078, 0xf7ffffff, 0x0f00ff83, 0x20000086, 0x20060083, 0xffff8fff, 0x00873fff, 0x00844000, 0x00007004, 0x0089f437, 0x00cd0100, 0x00921800, 0x00920c00, 0x00921c00, 0x008a1c00, 0x00860800, 0x008a3800, 0x00861000, 0x00897800, 0x00870400, 0x0089f800, 0x86400201, 0x01f80100, 0x0f000088, 0xf80b0087, 0x80000003, 0x00000007, 0x871fc3c0, 0x07f80b00, 0x0f800000, 0xc0000000, 0x00871fff, 0x000ff80b, 0x001f8000, 0xffc00000, 0x0b00871f, 0x00001ff0, 0x00001fc0, 0x1fffe000, 0xf00b0087, 0xc000003f, 0x0000063f, 0x870fffe0, 0xfff00b00, 0x3fe00000, 0xc0000004, 0x00870fff, 0x00fff00b, 0x0c3fe000, 0xfe000000, 0x0b008703, 0x0000fffc, 0x000cffe0, 0x027c0000, 0xfe0a0087, 0xe00000ff, 0x000008ff, 0x00883000, 0x01fffe05, 0x8dffe000, 0xffff0500, 0xffe00003, 0xff0b008d, 0xe00003ff, 0x000000ff, 0x87060004, 0xffff0b00, 0xfff00000, 0x02000000, 0x008703c1, 0x0007ff0a, 0x01fff000, 0x31710000, 0xff090088, 0xf000000f, 0x800003ff, 0x09008971, 0x000007fe, 0x0007fff0, 0x00896140, 0x0001fe09, 0x0ffffdf0, 0x88410100, 0xfec00b00, 0xfff80000, 0x80000fff, 0x00870600, 0x0008200a, 0xfffffc00, 0x0200c009, 0x700b0088, 0xfe000000, 0xc007ffff, 0x87010f80, 0x001e0b00, 0xfffc0000, 0x80e01eff, 0x00860107, 0x081bc00b, 0xfffc0000, 0xc3e07e7f, 0x0b008703, 0x000101c0, 0x7ffffe00, 0x07e7f0ff, 0xe00c0087, 0x00000001, 0x7fbffffc, 0x017ff7f8, 0xf00b0086, 0x00000081, 0x8ffffffc, 0x87ffffff, 0x83fc0c00, 0xf0000000, 0xfff7ffff, 0x8601ffff, 0x7ffa0700, 0xf0000000, 0xff83e77f, 0xfe070087, 0x000001ff, 0x83c00fe0, 0x853000ff, 0xff800800, 0x000003ff, 0x83c00f00, 0x85c800ff, 0xffc00e00, 0x000003ff, 0xcffb00f0, 0x043fffff, 0x0d008401, 0x07ffffc0, 0x61f00000, 0xffffcf67, 0x00850fff, 0xffffc00e, 0x8000000f, 0xfff707d7, 0x023fffff, 0xc00d0084, 0x003fffff, 0xafff8000, 0xffffffc3, 0x0900857f, 0x3fffffc0, 0xff800002, 0xff83e7ff, 0xe0070085, 0x03ffffff, 0x85fec000, 0x840100ff, 0xfff00700, 0x0001ff7f, 0xff85f890, 0x0083c000, 0xfff80108, 0x00007e1f, 0xff842840, 0x01c07f0f, 0x07000000, 0x6e03fffe, 0x7c000000, 0x0eff84fc, 0x00000101, 0xffffffc0, 0x00700603, 0x84ee7c00, 0x1f7f0eff, 0xff800000, 0x384fffff, 0xf00380f8, 0x0cff85fe, 0x8700007f, 0x7fffffff, 0x0003f878, 0x0eff87e0, 0xffc00000, 0x1e5c7bff, 0x80003ff8, 0x84df007f, 0x0d0084ff, 0xfc07f63e, 0x0000007f, 0xfffff820, 0x00841fef, 0xfd03c00c, 0x00fffc01, 0x00400000, 0x00875ffe, 0xf0e91204, 0x0083ffff, 0x1fa00302, 0x80060087, 0xfffff3f8, 0x0083f000, 0x00880300, 0xfffff004, 0x00c603ff );

const int rle_len_bytes = 156 << 2; // rle.length() << 2

int get_rle_byte(in int byte_index) {
    int long_val = rle[byte_index >> 2];
    return (long_val >> ((byte_index & 0x03) << 3)) & 0xff;
}

int get_uncompr_byte(in int byte_index) {
    int rle_index = 0;
    int cur_byte_index = 0;
    while (rle_index < rle_len_bytes) {
        int cur_rle_byte = get_rle_byte(rle_index);
        bool is_sequence = int(cur_rle_byte & 0x80) == 0;
        int count = (cur_rle_byte & 0x7f) + 1;
        if (byte_index >= cur_byte_index && byte_index < cur_byte_index + count) {
            if (is_sequence) {
                return get_rle_byte(rle_index + 1 + (byte_index - cur_byte_index));
            } else {
                return get_rle_byte(rle_index + 1);
            }
        } else {
            if (is_sequence) {
                rle_index += count + 1;
                cur_byte_index += count;
            } else {
                rle_index += 2;
                cur_byte_index += count;
            }
        }
    }
    return 0;
}

int getPaletteIndexXY(in ivec2 fetch_pos) {
    int palette_index = 0;
    if (fetch_pos.x >= 0 && fetch_pos.y >= 0
        && fetch_pos.x < int(bitmap_size.x) && fetch_pos.y < int(bitmap_size.y)) {
        int uncompr_byte_index = fetch_pos.y * (int(bitmap_size.x) >> 3) + (fetch_pos.x >> 3);
        int uncompr_byte = get_uncompr_byte(uncompr_byte_index);
        int bit_index = fetch_pos.x & 0x07;
        palette_index = (uncompr_byte >> bit_index) & 1;
    }
    return palette_index;
}

int getPaletteIndex(in vec2 uv) {
    ivec2 fetch_pos = ivec2(uv * bitmap_size);
    return getPaletteIndexXY(fetch_pos);
}

vec4 getColorFromPalette(in int palette_index) {
    int int_color = palette[palette_index];
    return vec4(float(int_color & 0xff) / 255.0,
                float((int_color >> 8) & 0xff) / 255.0,
                float((int_color >> 16) & 0xff) / 255.0,
                0);
}

vec4 getBitmapColor(in vec2 uv) {
    return getColorFromPalette(getPaletteIndex(uv));
}

vec4 renderBufferA(vec2 fragCoord) {
    vec2 uv = fragCoord / bitmap_size;
    return getBitmapColor(uv);
}

// ============ BUFFER B: Atmospheric Pressure Model ============
#define SIGMA vec4(6,4,0,0)
vec4 normpdf(float x) {
    return 0.39894 * exp(-0.5 * x * x / (SIGMA * SIGMA)) / SIGMA;
}

vec4 mslp(vec2 uv) {
    float lat = 180. * (uv.y * RENDERSIZE.y / MAPRES.y) - 90.;
    float land = texture(bufferA, uv).x;
    vec4 r;
    if (land > 0.) {
        r.x = 1012.5 - 6. * cos(lat * PI / 45.);
        r.y = 15. * sin(lat * PI / 90.);
    } else {
        r.x = 1014.5 - 20. * cos(lat * PI / 30.);
        r.y = 20. * sin(lat * PI / 35.) * abs(lat) / 90.;
    }
    return r;
}

vec4 bpass1(vec2 uv) {
    vec4 r = vec4(0);
    for (float i = -20.; i <= 20.; i++)
        r += mslp(uv + i * E / RENDERSIZE.xy) * normpdf(i);
    return r;
}

vec4 bpass2(vec2 uv) {
    vec4 r = vec4(0);
    for (float i = -20.; i <= 20.; i++)
        r += texture(bufferB, uv + i * N / RENDERSIZE.xy + PASS1) * normpdf(i);
    return r;
}

vec4 bpass3(vec2 uv) {
    vec4 c = texture(bufferB, uv + PASS2);
    // BPM-synced time with speed control
    float baseSpeed = 1.0 + bpm_sync * (syn_BPMTwitcher * 2.0 - 1.0);
    float t = mod(TIME * baseSpeed * speed, 12.);
    float delta = c.y * (1. - 2. * smoothstep(1.5, 4.5, t) + 2. * smoothstep(7.5, 10.5, t));
    return vec4(c.x + delta, 0, 0, 0);
}

// Dynamic vortex function - creates swirling disturbances
vec2 vortex(vec2 pos, vec2 center, float strength, float radius) {
    vec2 d = pos - center;
    float dist = length(d);
    float falloff = exp(-dist * dist / (radius * radius));
    return strength * falloff * vec2(-d.y, d.x) / (dist + 0.001);
}

vec4 bpass4(vec2 uv) {
    vec2 p = uv * RENDERSIZE.xy;
    float n = texture(bufferB, mod(p + N, MAPRES) / RENDERSIZE.xy + PASS3).x;
    float e = texture(bufferB, mod(p + E, MAPRES) / RENDERSIZE.xy + PASS3).x;
    float s = texture(bufferB, mod(p + S, MAPRES) / RENDERSIZE.xy + PASS3).x;
    float w = texture(bufferB, mod(p + W, MAPRES) / RENDERSIZE.xy + PASS3).x;
    vec2 grad = vec2(e - w, n - s) / 2.;
    float lat = 180. * fract(uv.y * RENDERSIZE.y / MAPRES.y) - 90.;
    vec2 coriolis = 15. * sin(lat * PI / 180.) * vec2(-grad.y, grad.x);
    vec2 v = coriolis - grad;
    
    // Normalize uv to full 0-1 range for vortex placement
    vec2 normUV = uv * 2.0; // Scale from 0-0.5 to 0-1 range
    
    // Add dynamic vortices affected by bass and turbulence slider
    float bassBoost = 1.0 + syn_BassLevel * turbulence_bass * 5.0;
    float t = TIME * speed * 0.5;
    
    // Multiple moving vortex centers spread across the map
    vec2 vortexV = vec2(0.0);
    
    // Vortex 1 - top left area
    vec2 c1 = vec2(0.2 + 0.15 * sin(t * 0.4), 0.75 + 0.15 * cos(t * 0.3));
    vortexV += vortex(normUV, c1, turbulence * 8.0 * bassBoost, 0.25);
    
    // Vortex 2 - top right area (opposite rotation)
    vec2 c2 = vec2(0.8 + 0.15 * cos(t * 0.35), 0.8 + 0.1 * sin(t * 0.45));
    vortexV -= vortex(normUV, c2, turbulence * 6.0 * bassBoost, 0.2);
    
    // Vortex 3 - middle left
    vec2 c3 = vec2(0.15 + 0.1 * sin(t * 0.5 + 1.0), 0.5 + 0.2 * cos(t * 0.25));
    vortexV += vortex(normUV, c3, turbulence * 7.0 * bassBoost, 0.22);
    
    // Vortex 4 - middle right (opposite rotation)
    vec2 c4 = vec2(0.85 + 0.1 * cos(t * 0.3 + 2.0), 0.45 + 0.15 * sin(t * 0.4));
    vortexV -= vortex(normUV, c4, turbulence * 5.0 * bassBoost, 0.18);
    
    // Vortex 5 - bottom center
    vec2 c5 = vec2(0.5 + 0.25 * sin(t * 0.2), 0.2 + 0.1 * cos(t * 0.35));
    vortexV += vortex(normUV, c5, turbulence * 6.0 * bassBoost, 0.2);
    
    // Vortex 6 - wandering vortex
    vec2 c6 = vec2(0.5 + 0.4 * sin(t * 0.15), 0.5 + 0.35 * cos(t * 0.2));
    vortexV -= vortex(normUV, c6, turbulence * 4.0 * bassBoost, 0.3);
    
    v += vortexV;
    
    // Add bass hits as sudden bursts at multiple locations
    if (syn_BassHits > 0.1) {
        float hitStrength = syn_BassHits * turbulence_bass * 15.0;
        vec2 burst1 = vec2(0.3 + 0.2 * sin(t), 0.7);
        vec2 burst2 = vec2(0.7 + 0.2 * cos(t), 0.3);
        v += vortex(normUV, burst1, hitStrength, 0.25);
        v -= vortex(normUV, burst2, hitStrength, 0.25);
    }
    
    return vec4(v, 0, 0);
}

vec4 renderBufferB(vec2 fragCoord) {
    vec2 uv = fragCoord / RENDERSIZE.xy;
    if (uv.x < 0.5) {
        if (uv.y < 0.5) {
            return bpass1(uv - PASS1);
        } else {
            return bpass2(uv - PASS2);
        }
    } else {
        if (uv.y < 0.5) {
            return bpass3(uv - PASS3);
        } else {
            return bpass4(uv - PASS4);
        }
    }
}

// ============ BUFFER C: Wind Flow Map ============
vec2 getVelocity(vec2 uv) {
    vec2 p = uv * MAPRES;
    if (p.x < 1.) p.x = 1.;
    vec2 v = texture(bufferB, p / RENDERSIZE.xy + vec2(0.5, 0.5)).xy;
    if (length(v) > 1.) v = normalize(v);
    return v;
}

vec2 getPosition(vec2 fragCoord) {
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            vec2 uv = (fragCoord + vec2(float(i), float(j))) / RENDERSIZE.xy;
            vec2 p = texture(bufferC, fract(uv)).xy;
            if (p == vec2(0)) {
                if (hash13(vec3(fragCoord + vec2(float(i), float(j)), float(FRAMECOUNT))) > 1e-4) continue;
                p = fragCoord + vec2(float(i), float(j)) + hash21(float(FRAMECOUNT)) - 0.5;
            } else if (hash13(vec3(fragCoord + vec2(float(i), float(j)), float(FRAMECOUNT))) < 8e-3) {
                continue;
            }
            vec2 v = getVelocity(uv);
            p = p + v;
            p.x = mod(p.x, RENDERSIZE.x);
            if (abs(p.x - fragCoord.x) < 0.5 && abs(p.y - fragCoord.y) < 0.5)
                return p;
        }
    }
    return vec2(0);
}

vec4 renderBufferC(vec2 fragCoord) {
    vec4 result;
    result.xy = getPosition(fragCoord);
    result.z = 0.9 * texture(bufferC, fragCoord / RENDERSIZE.xy).z;
    if (result.x > 0.) result.z = 1.;
    result.w = 1.0;
    return result;
}

// ============ IMAGE: Final Output ============

// Neon color palettes
vec3 getNeonColor(float angle, float neonHue) {
    // Vibrant neon colors cycling through hue
    vec3 col = 0.5 + 0.5 * cos(angle + neonHue * 6.28 + vec3(0, 2.1, 4.2));
    return pow(col, vec3(0.8)) * 1.2; // Boost brightness
}

vec4 renderImage(vec2 fragCoord) {
    // Calculate UVs - stretch to fill screen height
    vec2 screenUV = fragCoord / RENDERSIZE.xy;
    vec2 uv = screenUV;
    
    float lat = 180. * uv.y - 90.;
    vec2 p = uv * MAPRES;
    if (p.x < 1.) p.x = 1.;
    
    float land = texture(bufferA, uv).x;
    
    // Paper vs Dark Neon mode - smooth blend
    vec3 paperBg = vec3(0.9);
    vec3 paperLand = vec3(0.5);
    vec3 paperGrid = vec3(0., 0.5, 1.) * grid_opacity;
    
    vec3 darkBg = vec3(0.02, 0.02, 0.05);
    vec3 darkLand = vec3(0.1, 0.1, 0.15);
    vec3 darkGrid = vec3(0.0, 0.3, 0.6) * grid_opacity;
    
    vec3 bgColor = mix(paperBg, darkBg, dark_mode);
    vec3 landColor = mix(paperLand, darkLand, dark_mode);
    vec3 gridColor = mix(paperGrid, darkGrid, dark_mode);
    
    vec4 fragColor = vec4(bgColor, 1);
    if (0.25 < land && land < 0.75) fragColor.rgb = landColor;
    
    // For bufferB sampling
    vec2 bufBuv = p / RENDERSIZE.xy;
    
    // Wind flow
    vec2 v = texture(bufferB, bufBuv + PASS4).xy;
    float flow = texture(bufferC, fragCoord / RENDERSIZE.xy).z;
    
    // Color based on mode - smooth blend
    vec3 hue;
    float windAngle = atan(v.y, v.x);
    vec3 paperHue = vec3(1., 0.75, 0.5);
    vec3 neonHue = getNeonColor(windAngle, neon_hue + syn_BPMTwitcher * color_cycle);
    neonHue *= 1.0 + syn_BassLevel * bass_glow; // Bass glow effect
    hue = mix(paperHue, neonHue, dark_mode);
    
    float alpha = clamp(length(v), 0., 1.) * flow * wind_opacity;
    fragColor.rgb = mix(fragColor.rgb, hue, alpha);
    
    // Grid overlay - smooth blend between modes
    if (grid_opacity > 0.01) {
        if (mod(fragCoord.x, floor(RENDERSIZE.x / 36.)) < 1. ||
            mod(fragCoord.y, floor(RENDERSIZE.y / 18.)) < 1.) {
            float gridAlpha = mix(0.2, 0.4, dark_mode);
            fragColor.rgb = mix(fragColor.rgb, gridColor, gridAlpha);
        }
    }
    
    // Media blend with position offset
    if (media_blend > 0.01) {
        vec2 mediaUV = uv + (media_pos - vec2(0.5)) * 2.0;
        vec4 mediaCol = _textureMedia(mediaUV);
        if (media_mode < 0.33) {
            // Overlay mode
            fragColor.rgb = mix(fragColor.rgb, mediaCol.rgb, media_blend * mediaCol.a);
        } else if (media_mode < 0.66) {
            // Multiply mode
            vec3 blended = fragColor.rgb * mediaCol.rgb;
            fragColor.rgb = mix(fragColor.rgb, blended, media_blend * mediaCol.a);
        } else {
            // Screen mode
            vec3 blended = 1.0 - (1.0 - fragColor.rgb) * (1.0 - mediaCol.rgb);
            fragColor.rgb = mix(fragColor.rgb, blended, media_blend * mediaCol.a);
        }
    }
    
    // Final adjustments - smooth blend between paper and dark mode
    vec3 paperFinal = 0.9 - 0.8 * fragColor.rgb;
    vec3 darkFinal = pow(fragColor.rgb, vec3(0.9));
    fragColor.rgb = mix(paperFinal, darkFinal, dark_mode);
    
    return fragColor;
}

// ============ MAIN ENTRY POINT ============
vec4 renderMain(void) {
    vec2 fragCoord = _xy;
    
    if (PASSINDEX == 0) {
        return renderBufferA(fragCoord);
    } else if (PASSINDEX == 1) {
        return renderBufferB(fragCoord);
    } else if (PASSINDEX == 2) {
        return renderBufferC(fragCoord);
    } else {
        return renderImage(fragCoord);
    }
}
