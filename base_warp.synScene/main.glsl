// Base warp fBM - converted from Shadertoy
// Original: https://www.shadertoy.com/view/3cccrs

float colormap_red(float x) {
    if (x < 0.0) {
        return 54.0 / 255.0;
    } else if (x < 20049.0 / 82979.0) {
        return (829.79 * x + 54.51) / 255.0;
    } else {
        return 1.0;
    }
}

float colormap_green(float x) {
    if (x < 20049.0 / 82979.0) {
        return 0.0;
    } else if (x < 327013.0 / 810990.0) {
        return (8546482679670.0 / 10875673217.0 * x - 2064961390770.0 / 10875673217.0) / 255.0;
    } else if (x <= 1.0) {
        return (103806720.0 / 483977.0 * x + 19607415.0 / 483977.0) / 255.0;
    } else {
        return 1.0;
    }
}

float colormap_blue(float x) {
    if (x < 0.0) {
        return 54.0 / 255.0;
    } else if (x < 7249.0 / 82979.0) {
        return (829.79 * x + 54.51) / 255.0;
    } else if (x < 20049.0 / 82979.0) {
        return 127.0 / 255.0;
    } else if (x < 327013.0 / 810990.0) {
        return (792.02249341361393720147485376583 * x - 64.364790735602331034989206222672) / 255.0;
    } else {
        return 1.0;
    }
}

vec4 colormap(float x) {
    return vec4(colormap_red(x), colormap_green(x), colormap_blue(x), 1.0);
}

// RGB to HSV conversion
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB conversion
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float rand(vec2 n) { 
    return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
    vec2 ip = floor(p);
    vec2 u = fract(p);
    u = u*u*(3.0-2.0*u);

    float res = mix(
        mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
        mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
    return res*res;
}

const mat2 mtx = mat2( 0.80,  0.60, -0.60,  0.80 );

float fbm( vec2 p, float t )
{
    float f = 0.0;

    f += 0.500000*noise( p + t  ); p = mtx*p*2.02;
    f += 0.031250*noise( p ); p = mtx*p*2.01;
    f += 0.250000*noise( p ); p = mtx*p*2.03;
    f += 0.125000*noise( p ); p = mtx*p*2.01;
    f += 0.062500*noise( p ); p = mtx*p*2.04;
    f += 0.015625*noise( p + sin(t) );

    return f/0.96875;
}

float pattern( in vec2 p, float t )
{
    return fbm( p + fbm( p + fbm( p, t ), t ), t );
}

vec4 renderMain(void)
{
    vec2 uv = _xy / RENDERSIZE.x;
    
    // Always moving: base TIME + audio-reactive boost from syn_Time
    // syn_Time accumulates faster when music is active
    // Mix ensures there's always some movement even in silence
    float baseTime = TIME * 0.3;  // Slow constant movement
    float audioTime = syn_Time * 0.5;  // Audio-reactive acceleration
    float t = (baseTime + audioTime * bpm_sync) * warp_speed;
    
    float shade = pattern(uv, t);
    vec3 warpColor = colormap(shade).rgb;
    
    // Apply hue shift, saturation, brightness
    vec3 hsv = rgb2hsv(warpColor);
    hsv.x = fract(hsv.x + hue_shift);  // Hue shift (wraps around)
    hsv.y *= saturation;                // Saturation multiplier
    hsv.z *= brightness;                // Brightness multiplier
    warpColor = hsv2rgb(hsv);
    
    // Warp UV for media sampling based on pattern
    vec2 warpedUV = _uv + (shade - 0.5) * warp_amount;
    
    // Bass-reactive vibration/shake (only triggers above threshold)
    float bassActive = smoothstep(bass_threshold, bass_threshold + 0.1, syn_BassHits);
    float shake = bassActive * shake_intensity;
    warpedUV += shake * vec2(sin(TIME * 50.0), cos(TIME * 47.0));
    
    // Sample media with aspect-correct coords
    vec4 media = _textureMedia(warpedUV);
    
    // Blend media with warp colormap
    float blendAmount = media_blend + syn_MidLevel * audio_blend;
    vec3 finalColor = mix(warpColor, media.rgb, blendAmount * media.a);
    
    return vec4(finalColor, 1.0);
}
