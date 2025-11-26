// Bloom shader
// by Morgan McGuire, @CasualEffects, http://casual-effects.com

float square(int x) { return float(x * x); }

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    const int   blurRadius    = 5;
    const float blurVariance  = 0.1 * float(blurRadius * blurRadius);    
    vec2        invResolution = 1.0 / iResolution.xy;
    
    // Center tap
    vec4 sum = vec4(texture(iChannel0, fragCoord.xy * invResolution).rgb * 13.0, 13.0);
    
    for (int dx = -blurRadius; dx < blurRadius; dx += 2) {
        for (int dy = -blurRadius; dy < blurRadius; dy += 2) {
            // Bilinear taps at pixel corners
	        vec3 src = texture(iChannel0, (fragCoord.xy + vec2(dx, dy) + 0.5) * invResolution).rgb;
            float weight = exp2(-(square(dx) + square(dy)) / blurVariance);
            sum += vec4(src, 1.0) * weight;
        }
    }
    
	fragColor.xyz = pow(sum.rgb / sum.a, Color3(0.65));    
}

