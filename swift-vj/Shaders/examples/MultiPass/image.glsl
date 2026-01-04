// MultiPass Example - Image Pass
// Reads from BufA (iChannel0) and applies post-processing effects

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Sample Buffer A
    vec4 bufA = texture(iChannel0, uv);

    // Apply post-processing effects

    // 1. Chromatic aberration
    float aberration = 0.003;
    vec4 r = texture(iChannel0, uv + vec2(aberration, 0.0));
    vec4 g = texture(iChannel0, uv);
    vec4 b = texture(iChannel0, uv - vec2(aberration, 0.0));
    vec3 col = vec3(r.r, g.g, b.b);

    // 2. Sharpen
    vec2 texel = 1.0 / iResolution.xy;
    vec3 center = texture(iChannel0, uv).rgb * 5.0;
    vec3 neighbors = texture(iChannel0, uv + vec2(texel.x, 0.0)).rgb
                   + texture(iChannel0, uv - vec2(texel.x, 0.0)).rgb
                   + texture(iChannel0, uv + vec2(0.0, texel.y)).rgb
                   + texture(iChannel0, uv - vec2(0.0, texel.y)).rgb;
    vec3 sharpened = center - neighbors;
    col = mix(col, col + sharpened * 0.3, 0.5);

    // 3. Vignette
    vec2 q = uv * (1.0 - uv);
    float vignette = q.x * q.y * 15.0;
    vignette = pow(vignette, 0.15);
    col *= vignette;

    // 4. Color grading
    col = pow(col, vec3(0.95, 1.0, 1.05)); // Slight color shift
    col *= vec3(1.05, 1.0, 0.95); // Warm tint

    // 5. Contrast boost
    col = (col - 0.5) * 1.1 + 0.5;
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col, 1.0);
}
