// 2D rotation matrix function
mat2 rotate2D(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat2(c, -s, s, c);
}

#define hash(p) _hash12(p)
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(hash(i + vec2(0.0, 0.0)), 
                   hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), 
                   hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Fractal Brownian Motion for complex organic patterns
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for(int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// Create bubble/cellular patterns in the slime
float bubblePattern(vec2 uv, float t) {
    vec2 bubbleUV = uv * 8.0;
    float bubbles = 0.0;
    
    // Multiple layers of bubbles at different scales
    for(int i = 0; i < 3; i++) {
        float scale = pow(2.0, float(i));
        vec2 scaledUV = bubbleUV * scale + t * 0.1 * scale;
        // Drift the bubbles
        scaledUV += _noise(vec3(_uvc,TIME)) - vec2(0,bubble_float) + (3-i)*(0.5+0.25*sin(TIME));
        
        // Create cellular noise pattern
        vec2 cellID = floor(scaledUV);
        vec2 cellUV = fract(scaledUV) - 0.5;
        
        // Random bubble center in each cell
        vec2 bubbleCenter = vec2(
            hash(cellID) - 0.5,
            _noise(vec3(vec2(hash(cellID), hash(cellID + 100.0)),0.2*(TIME+syn_BassTime))) - 0.5
        );
        bubbleCenter *= 0.5; // Keep bubbles within cell
        
        float bubbleSize = 0.1 + 0.2 * hash(cellID + 200.0);
        float dist = length(cellUV - bubbleCenter);
        
        // Create smooth bubble with surface tension effect
        float bubble = smoothstep(bubbleSize + 0.1, bubbleSize - 0.05, dist);
        bubble *= (1.0 + 0.3 * sin(t * 2.0 + hash(cellID) * 10.0));
        
        bubbles += bubble / scale;
        // bubbles = max(bubbles, bubble / scale);
    }
    
    return clamp(bubbles, 0.0, 1.0);
}

// Different slime movement patterns based on slime_options
vec2 getSlimeMovementPattern(vec2 uv, float t, float viscosity, float detailLevel, int movementType) {
    vec2 distorted = uv;
    
    if (movementType == 0) {
        // 0: Classic Slime - original organic movement
        float primaryFlow = fbm(uv * 1.5 + t * 0.1 / viscosity, 4);
        distorted += vec2(
            sin(primaryFlow * 6.28318 + t * 0.3) * 0.15,
            cos(primaryFlow * 6.28318 + t * 0.2) * 0.12
        );
    }
    else if (movementType == 1) {
        // 1: Rain Drip - vertical flowing movement
        float dropFlow = fbm(vec2(uv.x * 3.0, uv.y * 0.5) + t * 0.3, 3);
        distorted.y += sin(dropFlow * PI + t * 1.5) * 0.4;
        distorted.x += sin(uv.y * 8.0 + t * 0.8) * 0.05; // slight horizontal wiggle
        
        // Add drip streaks
        float streaks = sin(uv.x * 15.0 + t * 2.0) * 0.02;
        distorted.y += streaks;
    }
    else if (movementType == 2) {
        // 2: Lava Flow - slow, thick horizontal movement
        float lavaFlow = fbm(vec2(uv.x * 0.8, uv.y * 2.0) + t * 0.05, 4);
        distorted.x += sin(lavaFlow * 6.28318 + t * 0.2) * 0.25;
        distorted.y += cos(lavaFlow * PI + t * 0.1) * 0.08;
        
        // Add lava bubble clusters
        float bubbles = fbm(uv * 4.0 + t * 0.1, 2);
        distorted += vec2(sin(bubbles * 12.56), cos(bubbles * 12.56)) * 0.06;
    }
    else if (movementType == 3) {
        // 3: Blob/Cellular - contained, blobby movement
        vec2 center = vec2(sin(t * 0.3) * 0.2, cos(t * 0.25) * 0.15);
        vec2 toCenter = center - uv;
        float distToCenter = length(toCenter);
        
        // Pulsing blob expansion/contraction
        float pulse = 1.0 + sin(t * 1.2) * 0.3;
        distorted = center + toCenter * pulse;
        
        // Add cellular structure
        float cellular = fbm(distorted * 6.0 + t * 0.2, 3);
        distorted += vec2(sin(cellular * 6.28318), cos(cellular * 6.28318)) * 0.08;
    }
    else if (movementType == 4) {
        // 4: Liquid Metal - fast, smooth flowing
        float metalFlow = fbm(uv * 2.0 + t * 0.5, 3);
        vec2 flowVelocity = vec2(
            cos(metalFlow * 6.28318 + t * 2.0),
            sin(metalFlow * 6.28318 + t * 1.8)
        );
        distorted += flowVelocity * 0.2;
        
        // Add mercury-like surface tension
        float tension = fbm(distorted * 8.0, 2);
        distorted += normalize(vec2(tension, tension)) * 0.05;
    }
    else if (movementType == 5) {
        // 5: Honey - very slow, thick movement
        float honeyFlow = fbm(uv * 1.0 + t * 0.02, 5);
        distorted += vec2(
            sin(honeyFlow * PI + t * 0.1) * 0.08,
            cos(honeyFlow * PI + t * 0.08) * 0.06
        );
        
        // Add thick, viscous streams
        float streams = sin(uv.y * 12.0 + t * 0.3) * 0.03;
        distorted.x += streams;
    }
    else if (movementType == 6) {
        // 6: Water Ripples - circular wave patterns
        vec2 center = vec2(0.0, 0.0);
        float distFromCenter = length(uv - center);
        
        // Multiple ripple sources
        for(int i = 0; i < 3; i++) {
            vec2 rippleCenter = vec2(
                sin(t * 0.3 + float(i) * 2.0) * 0.3,
                cos(t * 0.25 + float(i) * 2.5) * 0.3
            );
            float rippleDist = length(uv - rippleCenter);
            float ripple = sin(rippleDist * 20.0 - t * 4.0) * exp(-rippleDist * 2.0);
            
            vec2 rippleDir = normalize(uv - rippleCenter);
            distorted += rippleDir * ripple * 0.05;
        }
    }
    else if (movementType == 7) {
        // 7: Electric Plasma - chaotic, electric-like movement
        float electric1 = fbm(uv * 8.0 + t * 1.5, 2);
        float electric2 = fbm(uv * 12.0 + t * 2.0 + 100.0, 2);
        
        distorted += vec2(
            sin(electric1 * 25.12 + t * 3.0) * 0.15,
            cos(electric2 * 31.41 + t * 2.5) * 0.15
        );
        
        // Add electrical arcs
        float arcs = sin(uv.x * 30.0 + t * 5.0) * sin(uv.y * 25.0 + t * 4.0);
        distorted += vec2(arcs, -arcs) * 0.08;
    }
    else if (movementType == 8) {
        // 8: Organic Growth - expanding/contracting organic patterns
        float growth = sin(t * 0.8) * 0.5 + 0.5; // 0 to 1
        float organicPattern = fbm(uv * 3.0, 4);
        
        // Scale based on growth phase
        vec2 scaledUV = uv * (1.0 + growth * 0.5);
        distorted = scaledUV;
        
        // Add organic tendrils
        float tendrils = fbm(scaledUV * 6.0 + t * 0.3, 3);
        distorted += vec2(
            sin(tendrils * 6.28318) * growth * 0.12,
            cos(tendrils * 6.28318) * growth * 0.12
        );
    }
    else if (movementType == 9) {
        // 9: Tornado/Spiral - spiral movement patterns
        float angle = atan(uv.y, uv.x);
        float radius = length(uv);
        
        // Spiral rotation
        float spiralSpeed = t * 1.0 + radius * 5.0;
        angle += spiralSpeed;
        
        // Convert back to cartesian with spiral distortion
        vec2 spiralPos = vec2(cos(angle), sin(angle)) * radius;
        distorted = spiralPos;
        
        // Add spiral arms
        float spiralArms = sin(angle * 3.0 + t * 2.0) * 0.1;
        distorted += vec2(cos(angle + 1.57), sin(angle + 1.57)) * spiralArms;
    }
    
    // Common secondary details for all movement types
    vec2 turbulence = vec2(
        fbm(distorted * 3.0 + t * 0.2, 3),
        fbm(distorted * 3.0 + t * 0.15 + 100.0, 3)
    ) * 0.08 * detailLevel;
    distorted += turbulence;
    
    // Fine scale surface ripples
    vec2 ripples = vec2(
        noise(distorted * 12.0 + t * 0.5),
        noise(distorted * 12.0 + t * 0.4 + 50.0)
    ) * 0.03 * detailLevel;
    distorted += ripples;
    
    return distorted;
}

// Advanced slime flow distortion (now using movement patterns)
vec2 slimeDistortion(vec2 uv, float time, float viscosity, float detailLevel, int movementType) {
    vec2 distorted = getSlimeMovementPattern(uv, time, viscosity, detailLevel, movementType);
    
    // Surface tension effects - creates slime "strings" and cohesion
    float tension = fbm(distorted * 6.0, 2);
    vec2 tensionGrad = vec2(
        fbm(distorted * 6.0 + vec2(0.01, 0.0), 2) - tension,
        fbm(distorted * 6.0 + vec2(0.0, 0.01), 2) - tension
    ) / 0.01;
    distorted += tensionGrad * 0.05 * viscosity;
    
    return distorted;
}

// Create slime thickness variation for 3D depth effect
float slimeThickness(vec2 uv, float time) {
    // Base thickness variation
    float thickness = 0.5 + 0.3 * fbm(uv * 2.0 + time * 0.05, 4);
    
    // Add flowing streams
    float streams = 0.0;
    for(int i = 0; i < 3; i++) {
        float angle = float(i) * 2.094 + time * 0.1;
        vec2 streamDir = vec2(cos(angle), sin(angle));
        float streamPos = dot(uv, streamDir);
        streams += exp(-pow((streamPos + sin(time * 0.3 + float(i))), 2.0) * 8.0);
    }
    thickness += streams * 0.3;
    
    return clamp(thickness, 0.1, 1.0);
}

// Audio reactive brightness calculation
float calculateAudioBrightness(float audioReactiveness, vec2 uv) {
    // Base brightness multiplier
    float baseBrightness = 1.0;
    
    // Use syn_BassLevel for continuous brightness modulation
    float bassBrightness = 1.0 + (syn_BassLevel * audioReactiveness * 0.8);
    
    // Use syn_BassHits for sudden brightness flashes
    float hitFlash = syn_BassHits * audioReactiveness * 1.2;
    
    // Use syn_BassPresence for overall energy level
    float presenceBoost = 1.0 + (syn_BassPresence * audioReactiveness * 0.5);
    
    // Combine all audio influences
    float totalBrightness = baseBrightness * bassBrightness * presenceBoost + hitFlash;
    
    // Add spatial variation based on UV coordinates for more interesting effects
    float spatialMod = 1.0 + sin(length(uv) * 8.0) * 0.2 * syn_BassLevel * audioReactiveness;
    totalBrightness *= spatialMod;
    
    // Clamp to reasonable range to prevent overexposure
    return clamp(totalBrightness, 0.2, 3.0);
}

vec3 getPaletteColor(float t, int paletteIndex) {
    // Normalize t to 0-1 range for consistent palette mapping
    t = clamp(t, 0.0, 1.0);
    
    vec3 col;
    
    if (paletteIndex == 0) {
        // Original palette
        col.r = t + 0.443;
        col.g = t + 0.502;
        col.b = t - 0.324;
    }
    else if (paletteIndex == 1) {
        // Sunset palette (warm oranges and reds)
        col.r = 0.8 + 0.2 * sin(t * PI);
        col.g = 0.4 + 0.4 * sin(t * PI + 1.0);
        col.b = 0.1 + 0.3 * sin(t * PI + 2.0);
    }
    else if (paletteIndex == 2) {
        // Ocean palette (blues and teals)
        col.r = 0.1 + 0.3 * sin(t * PI + 4.0);
        col.g = 0.3 + 0.4 * sin(t * PI + 2.0);
        col.b = 0.6 + 0.4 * sin(t * PI);
    }
    else if (paletteIndex == 3) {
        // Rainbow palette
        col.r = 0.5 + 0.5 * sin(t * 6.28318 + 0.0);
        col.g = 0.5 + 0.5 * sin(t * 6.28318 + 2.094);
        col.b = 0.5 + 0.5 * sin(t * 6.28318 + 4.188);
    }
    else if (paletteIndex == 4) {
        // Neon palette (bright cyans and magentas)
        col.r = 0.5 + 0.5 * sin(t * 12.56 + 1.0);
        col.g = 0.2 + 0.6 * sin(t * 9.42 + 3.0);
        col.b = 0.7 + 0.3 * sin(t * 15.71 + 5.0);
    }
    else if (paletteIndex == 5) {
        // Fire palette (reds, oranges, yellows)
        col.r = 0.7 + 0.3 * sin(t * PI);
        col.g = 0.2 + 0.6 * t;
        col.b = 0.0 + 0.4 * t * t;
    }
    else if (paletteIndex == 6) {
        // Ice palette (cool blues and whites)
        col.r = 0.6 + 0.4 * t;
        col.g = 0.7 + 0.3 * t;
        col.b = 0.8 + 0.2 * sin(t * PI);
    }
    else if (paletteIndex == 7) {
        // Forest palette (greens and earth tones)
        col.r = 0.2 + 0.3 * sin(t * PI + 3.0);
        col.g = 0.4 + 0.5 * sin(t * PI);
        col.b = 0.1 + 0.2 * sin(t * PI + 1.5);
    }
    else if (paletteIndex == 8) {
        // Purple Galaxy palette
        col.r = 0.4 + 0.4 * sin(t * PI + 2.0);
        col.g = 0.1 + 0.3 * sin(t * PI + 4.0);
        col.b = 0.6 + 0.4 * sin(t * PI);
    }
    else if (paletteIndex == 9) {
        // Pastel palette (soft colors)
        col.r = 0.7 + 0.3 * sin(t * PI);
        col.g = 0.6 + 0.3 * sin(t * PI + 2.0);
        col.b = 0.8 + 0.2 * sin(t * PI + 4.0);
    }
    else if (paletteIndex == 10) {
        // Desert palette (browns, tans, oranges)
        col.r = 0.6 + 0.3 * sin(t * PI + 1.0);
        col.g = 0.4 + 0.4 * t;
        col.b = 0.2 + 0.2 * sin(t * PI + 5.0);
    }
    else if (paletteIndex == 11) {
        // Electric palette (bright blues and whites)
        col.r = 0.2 + 0.6 * t * t;
        col.g = 0.4 + 0.6 * t;
        col.b = 0.8 + 0.2 * sin(t * 6.28318);
    }
    else if (paletteIndex == 12) {
        // Toxic palette (greens and yellows)
        col.r = 0.3 + 0.4 * sin(t * 6.28318 + 2.0);
        col.g = 0.6 + 0.4 * sin(t * PI);
        col.b = 0.1 + 0.3 * sin(t * 9.42 + 4.0);
    }
    else if (paletteIndex == 13) {
        // Cherry Blossom palette (pinks and whites)
        col.r = 0.8 + 0.2 * sin(t * PI);
        col.g = 0.4 + 0.4 * sin(t * PI + 1.5);
        col.b = 0.6 + 0.3 * sin(t * PI + 3.0);
    }
    else if (paletteIndex == 14) {
        // Monochrome Red
        float intensity = 0.3 + 0.7 * sin(t * PI);
        col = vec3(intensity, intensity * 0.2, intensity * 0.1);
    }
    else if (paletteIndex == 15) {
        // Monochrome Blue
        float intensity = 0.3 + 0.7 * sin(t * PI);
        col = vec3(intensity * 0.1, intensity * 0.3, intensity);
    }
    else if (paletteIndex == 16) {
        // Lava palette (deep reds and oranges)
        col.r = 0.5 + 0.5 * sin(t * PI + 1.0);
        col.g = 0.1 + 0.4 * t * t;
        col.b = 0.0 + 0.2 * t * t * t;
    }
    else if (paletteIndex == 17) {
        // Aurora palette (greens, blues, purples)
        col.r = 0.2 + 0.4 * sin(t * 6.28318 + 4.0);
        col.g = 0.5 + 0.5 * sin(t * PI);
        col.b = 0.3 + 0.5 * sin(t * 9.42 + 2.0);
    }
    
    return clamp(col, 0.0, 1.0);
}

vec3 applyColorEffect(vec3 originalColor, int effectIndex) {
    vec3 col = originalColor;
    
    if (effectIndex == 0) {
        // 0: Normal - no effect
        return col;
    }
    else if (effectIndex == 1) {
        // 1: Sepia - vintage sepia tone
        float gray = dot(col, vec3(0.299, 0.587, 0.114));
        col.r = gray * 1.2;
        col.g = gray * 1.0;
        col.b = gray * 0.8;
    }
    else if (effectIndex == 2) {
        // 2: Posterize - reduce color levels for artistic effect
        float levels = 4.0;
        col = floor(col * levels) / levels;
    }
    else if (effectIndex == 3) {
        // 3: Vintage - warm vintage color grading
        col.r = col.r * 1.1 + 0.05;
        col.g = col.g * 0.95 + 0.02;
        col.b = col.b * 0.8;
        col = clamp(col, 0.0, 1.0);
    }
    else if (effectIndex == 4) {
        // 4: Negative Film - film negative effect
        col = vec3(1.0) - col;
        col = pow(col, vec3(0.8)); // Adjust gamma for film look
    }
    
    return _nclamp(col);
}

// Media blending functions
vec3 blendMedia(vec3 baseColor, vec3 mediaColor, int blendMode, float opacity) {
    vec3 result = baseColor;
    
    if (blendMode == 0) {
        // 0: Normal - standard alpha blend
        result = mix(baseColor, mediaColor, opacity);
    }
    else if (blendMode == 1) {
        // 1: Multiply - darkens the image
        result = mix(baseColor, baseColor * mediaColor, opacity);
    }
    else if (blendMode == 2) {
        // 2: Screen - lightens the image
        vec3 screen = vec3(1.0) - (vec3(1.0) - baseColor) * (vec3(1.0) - mediaColor);
        result = mix(baseColor, screen, opacity);
    }
    else if (blendMode == 3) {
        // 3: Overlay - combines multiply and screen
        vec3 overlay;
        overlay.r = (baseColor.r < 0.5) ? (2.0 * baseColor.r * mediaColor.r) : (1.0 - 2.0 * (1.0 - baseColor.r) * (1.0 - mediaColor.r));
        overlay.g = (baseColor.g < 0.5) ? (2.0 * baseColor.g * mediaColor.g) : (1.0 - 2.0 * (1.0 - baseColor.g) * (1.0 - mediaColor.g));
        overlay.b = (baseColor.b < 0.5) ? (2.0 * baseColor.b * mediaColor.b) : (1.0 - 2.0 * (1.0 - baseColor.b) * (1.0 - mediaColor.b));
        result = mix(baseColor, overlay, opacity);
    }
    else if (blendMode == 4) {
        // 4: Add - adds the colors together
        result = mix(baseColor, clamp(baseColor + mediaColor, 0.0, 1.0), opacity);
    }
    else if (blendMode == 5) {
        // 5: Subtract - subtracts media from base
        result = mix(baseColor, clamp(baseColor - mediaColor, 0.0, 1.0), opacity);
    }
    else if (blendMode == 6) {
        // 6: Difference - absolute difference
        result = mix(baseColor, abs(baseColor - mediaColor), opacity);
    }
    
    return clamp(result, 0.0, 1.0);
}

// Sample media with distortion - Fixed for 1920x1080 resolution
vec3 sampleMediaWithDistortion(vec2 distortedUV, float distortAmount, vec2 offset) {
    vec2 mediaUV = _uv + offset;
    
    // Convert distorted UV back to screen coordinates for media sampling
    vec2 distortedScreenCoord = (distortedUV * min(RENDERSIZE.x, RENDERSIZE.y)) + RENDERSIZE.xy;
    distortedScreenCoord /= 1.2; // Reverse the 1.2 scaling factor from original UV calculation
    vec2 distortedMediaUV = distortedScreenCoord / RENDERSIZE.xy;
    
    // Apply same offset to distorted coordinates
    distortedMediaUV = (distortedMediaUV - 0.5) + 0.5;
    distortedMediaUV += offset;
    
    // Blend between original and distorted UVs based on distortAmount
    vec2 finalMediaUV = mix(mediaUV, distortedMediaUV, distortAmount);
    
    // Handle edge behavior - you can change this to fract() for tiling
    finalMediaUV = clamp(finalMediaUV, 0.0, 1.0);
    
    // Sample the media texture (syn_Media) at full resolution
    // vec3 mediaColor = texture(syn_Media, finalMediaUV).rgb;
    vec3 mediaColor = _textureMedia(finalMediaUV).rgb;
    
    return mediaColor;
}

vec4 renderMainImage() {
    vec4 fragColor = vec4(0.0);
    vec2 uv = (1.2 * (_uvc-.5));
    
    // Apply camera rotation
    uv *= rotate2D(camera_rotation);
    
    // Get control parameters from sliders
    float viscosity = slime_viscosity;
    float bubbleIntensity = bubble_intensity;  
    float detailLevel = detail_level;
    int movementType = int(floor(slime_options));
    movementType = clamp(movementType, 0, 9);
    
    // Audio reactiveness parameter
    float audioReactiveness = audioreactiveness;
    
    // Media parameters
    float mediaToggle = media_toggle;
    int blendMode = int(floor(media_blend_mode));
    blendMode = clamp(blendMode, 0, 6);
    float mediaOpacity = media_opacity;
    float mediaDistortAmount = media_distort;
    vec2 mediaOffset = vec2(media_offset_x, media_offset_y);
    
    // Apply advanced slime distortion with movement patterns
    vec2 distortedUV = slimeDistortion(uv, TIME, viscosity, detailLevel, movementType);
    
    // Enhanced original wave pattern with movement-specific adjustments
    float waveIntensity = 1.0;
    float waveSpeed = 1.0;
    
    // Adjust wave parameters based on movement type
    if (movementType == 1) { // Rain drip
        waveIntensity = 0.3;
        waveSpeed = 2.0;
    } else if (movementType == 2) { // Lava flow
        waveIntensity = 0.6;
        waveSpeed = 0.3;
    } else if (movementType == 4) { // Liquid metal
        waveIntensity = 1.5;
        waveSpeed = 1.8;
    } else if (movementType == 5) { // Honey
        waveIntensity = 0.4;
        waveSpeed = 0.2;
    } else if (movementType == 7) { // Electric plasma
        waveIntensity = 2.0;
        waveSpeed = 3.0;
    }
    
    for(float i = 2.15; i < 7.150; i++){
        float frequency = i * i;
        float amplitude = (0.1 / i) * waveIntensity;
        
        // Multiple wave directions for more organic movement
        distortedUV.y += amplitude * sin(distortedUV.x * frequency + TIME * 0.5 * waveSpeed / viscosity);
        distortedUV.x += amplitude * 0.7 * cos(distortedUV.y * frequency * 0.8 + TIME * 0.3 * waveSpeed / viscosity);
        
        // Add phase-shifted waves for complexity
        distortedUV.y += amplitude * 0.5 * sin(distortedUV.x * frequency * 1.3 + TIME * 0.7 * waveSpeed / viscosity + 1.57);
    }
    
    // Calculate slime thickness for 3D depth
    float thickness = slimeThickness(distortedUV, TIME);
    
    // Add bubble pattern
    float bubbles = bubblePattern(mix(uv,distortedUV,bubble_distort), TIME * 0.5);
    
    // Combine thickness and bubbles for final texture value
    float textureValue = thickness + bubbles * bubbleIntensity * 0.3;
    
    // Convert slider values to integers for palette and effect selection
    int paletteIndex = int(floor(color_palette));
    paletteIndex = clamp(paletteIndex, 0, 17);
    
    int effectIndex = int(color_effects);
    
    // Use texture value for palette mapping with enhanced contrast
    float t = clamp(textureValue, 0.0, 1.0);
    t = pow(t, 0.8); // Adjust gamma for better contrast
    
    // Get base color from palette
    vec3 col = getPaletteColor(t, paletteIndex);
    
    // Add slime-specific lighting effects
    // Simulate subsurface scattering in thick areas
    float subsurface = pow(thickness, 1.5);
    col = mix(col, col * 1.3, subsurface * 0.4);
    
    // Add bubble highlights
    col += vec3(0.2, 0.3, 0.4) * bubbles * bubbleIntensity * 0.5;
    
    // Add surface shine/reflection based on flow direction
    vec2 flowGradient = vec2(
        slimeThickness(distortedUV + vec2(0.01, 0.0), TIME) - thickness,
        slimeThickness(distortedUV + vec2(0.0, 0.01), TIME) - thickness
    ) / 0.01;
    float shine = pow(max(0.0, -dot(normalize(flowGradient), vec2(0.707, 0.707))), 3.0);
    col += vec3(0.1, 0.15, 0.2) * shine * 0.6;
    
    // Apply audio reactive brightness modulation
    float audioBrightness = calculateAudioBrightness(audioReactiveness, uv);
    col *= audioBrightness;
    
    // Apply color effect
    col = applyColorEffect(col, effectIndex);
    
    // Add media integration if toggled on
    if (mediaToggle > 0.5) {
        // Sample media with optional distortion using proper screen coordinates
        vec3 mediaColor = sampleMediaWithDistortion(distortedUV, mediaDistortAmount, mediaOffset);
        
        // Blend media with slime effect
        col = blendMedia(col, mediaColor, blendMode, mediaOpacity);
    }
    
    fragColor = vec4(col, 1.0);
    return fragColor; 
}

vec4 renderMain(){
    if(PASSINDEX == 0){
        // return vec4(bubblePattern(_uv,TIME));
        return renderMainImage();
    }
}