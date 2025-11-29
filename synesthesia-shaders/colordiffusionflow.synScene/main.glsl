

///////////////////////////////////////////
// ColorDiffusionFlow  by mojovideotech
//
// based on :
// glslsandbox.com/\e#35553.0
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
// Audio reactivity + Media flow-around for Synesthesia
///////////////////////////////////////////


#ifdef GL_ES
precision mediump float;
#endif
 
#define pi 3.141592653589793

// Get media mask value with threshold and softness
// Uses _textureMedia for aspect-correct sampling
float getMediaMask(vec2 uv, float audioBoost) {
    vec3 mediaSample = _textureMedia(uv).rgb;
    float luma = dot(mediaSample, vec3(0.299, 0.587, 0.114));
    
    // Audio-reactive threshold
    float thresh = media_threshold - audioBoost * 0.2;
    
    // Apply threshold with soft edges
    float mask = smoothstep(thresh - media_edge_softness, thresh + media_edge_softness, luma);
    
    // Invert if requested
    if (media_invert > 0.5) mask = 1.0 - mask;
    
    return mask;
}

// Compute gradient of media mask for flow deflection
vec2 getMediaGradient(vec2 uv, float audioBoost) {
    vec2 texel = 1.0 / RENDERSIZE.xy;
    float dx = getMediaMask(uv + vec2(texel.x, 0.0), audioBoost) 
             - getMediaMask(uv - vec2(texel.x, 0.0), audioBoost);
    float dy = getMediaMask(uv + vec2(0.0, texel.y), audioBoost) 
             - getMediaMask(uv - vec2(0.0, texel.y), audioBoost);
    return vec2(dx, dy) * 0.5;
}

vec4 renderMain() { 
    vec4 out_FragColor = vec4(0.0);

    // === HEARTBEAT PULSE from bass ===
    float heartbeat = syn_BassLevel * 0.5 + syn_BassHits * 0.8;
    float pulseScale = 1.0 + heartbeat * pulse_strength * audio_reactivity * 0.12;
    
    // === TWITCH EFFECT from button ===
    float twitchOffset = twitch_button * 0.08 * sin(TIME * 60.0);
    
    // === MEDIA SETUP ===
    float mediaAudioBoost = (syn_BassLevel + syn_HighLevel) * media_audio_react * audio_reactivity;
    float mediaMask = getMediaMask(_uv, mediaAudioBoost);
    vec2 mediaGrad = getMediaGradient(_uv, mediaAudioBoost);
    
    // Audio-reactive edge pulsing
    float edgePulse = 1.0 + mediaAudioBoost * 0.5;

    float T = TIME * rate1;
    float TT = TIME * rate2;
    vec2 p = (2.0 * _uv);
    
    // Apply breathing pulse to starting position
    p = (p - 1.0) * pulseScale + 1.0;
    p += twitchOffset;
    
    // === MEDIA FLOW DEFLECTION ===
    // Push coordinates away from media edges (gradient perpendicular = flow around)
    vec2 flowDeflect = vec2(-mediaGrad.y, mediaGrad.x); // Perpendicular to gradient
    float deflectStrength = media_influence * mediaMask * edgePulse * 2.0;
    p += flowDeflect * deflectStrength;
    
    for(int i = 1; i < 11; i++) {
        vec2 newp = p;
        float ii = float(i);
        
        // Modulate depth with bass for organic living pulse
        float depthPulse = 1.0 + heartbeat * pulse_strength * audio_reactivity * 0.25;
        float dX = depthX * depthPulse;
        float dY = depthY * depthPulse;
        
        // Reduce wave amplitude near media for smoother flow-around
        float mediaWaveDampen = 1.0 - mediaMask * media_influence * 0.5;
        dX *= mediaWaveDampen;
        dY *= mediaWaveDampen;
        
        newp.x += dX/ii * sin(ii*pi*p.y + T + nudge + cos((TT/(5.0*ii))*ii));
        newp.y += dY/ii * cos(ii*pi*p.x + TT + nudge + sin((T/(5.0*ii))*ii));
        
        float timeline = log(max(TIME + 1.0, 1.0)) / loopcycle;
        p = newp + timeline;
    }
    
    // === HIGH FREQUENCY SHIMMER ===
    float shimmer = syn_HighLevel * shimmer_amount * audio_reactivity;
    float colorShift = shimmer * sin(TIME * 4.0) * 0.4;
    
    vec3 col = vec3(
        cos(p.x + p.y + 3.0*color1 + colorShift) * 0.5 + 0.5,
        sin(p.x + p.y + 6.0*cycle1 + colorShift*0.7) * 0.5 + 0.5,
        (sin(p.x + p.y + 9.0*color2) + cos(p.x + p.y + 12.0*cycle2 + colorShift*1.3)) * 0.25 + 0.5
    );
    
    // Original squaring for contrast
    col = col * col;
    
    // === MEDIA BLEND MODES ===
    vec3 mediaColor = _textureMedia(_uv).rgb;
    float edgeDetect = length(mediaGrad) * 10.0; // Edge detection for glow
    
    if (media_blend_mode < 0.5) {
        // Mode 0: Flow Around - pattern flows, media darkens/reveals
        col = mix(col, col * 0.1, mediaMask * media_influence);
    } else if (media_blend_mode < 1.5) {
        // Mode 1: Mask Reveal - media cuts through to show pattern
        col = mix(vec3(0.0), col, 1.0 - mediaMask * media_influence);
    } else {
        // Mode 2: Tint Blend - media tints the flowing pattern
        col = mix(col, col * mediaColor * 2.0, mediaMask * media_influence);
    }
    
    // === MEDIA EDGE GLOW ===
    vec3 glowColor = vec3(0.8, 0.9, 1.0) * (1.0 + mediaAudioBoost);
    col += edgeDetect * media_edge_glow * glowColor * edgePulse;
    
    // === FLASH BUTTON ===
    col = mix(col, vec3(1.0), flash_button * 0.85);
    
    // === INVERT BUTTON ===
    col = mix(col, 1.0 - col, invert_button);
    
    out_FragColor = vec4(col, 1.0);
    return out_FragColor;
} 
