// Feedback Example - Image Pass
// Reads Buffer A (iChannel0) with accumulated trails and enhances output

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Sample the feedback buffer
    vec4 bufA = texture(iChannel0, uv);

    // Apply color enhancement
    vec3 col = bufA.rgb;

    // Bloom effect: sample multiple offsets
    vec2 texel = 1.0 / iResolution.xy;
    vec3 bloom = vec3(0.0);
    float bloomSize = 3.0;

    for (float x = -2.0; x <= 2.0; x += 1.0) {
        for (float y = -2.0; y <= 2.0; y += 1.0) {
            vec2 offset = vec2(x, y) * texel * bloomSize;
            bloom += texture(iChannel0, uv + offset).rgb;
        }
    }
    bloom /= 25.0;

    // Add bloom to brightest parts
    float brightness = dot(col, vec3(0.299, 0.587, 0.114));
    col += bloom * smoothstep(0.3, 0.8, brightness) * 0.5;

    // Color grading: boost saturation
    float gray = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(gray), col, 1.3);

    // Gamma correction
    col = pow(col, vec3(0.9));

    // Vignette
    vec2 q = uv * (1.0 - uv);
    float vignette = pow(q.x * q.y * 15.0, 0.2);
    col *= vignette;

    fragColor = vec4(col, 1.0);
}
