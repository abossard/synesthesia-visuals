// SinglePass Example - Procedural Pattern
// A simple shader demonstrating the single-pass Image shader format

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Normalized coordinates (0 to 1)
    vec2 uv = fragCoord / iResolution.xy;

    // Center and aspect correct
    vec2 p = uv * 2.0 - 1.0;
    p.x *= iResolution.x / iResolution.y;

    // Animated pattern
    float t = iTime * 0.5;

    // Create concentric rings
    float r = length(p);
    float ring = sin(r * 10.0 - t * 3.0) * 0.5 + 0.5;

    // Create spiral
    float a = atan(p.y, p.x);
    float spiral = sin(a * 5.0 + r * 8.0 - t * 2.0) * 0.5 + 0.5;

    // Combine patterns
    vec3 col = vec3(0.0);
    col.r = ring * 0.8;
    col.g = spiral * 0.7;
    col.b = (ring + spiral) * 0.4;

    // Vignette
    float vignette = 1.0 - smoothstep(0.5, 1.5, r);
    col *= vignette;

    // Mouse interaction
    if (iMouse.z > 0.0) {
        vec2 mouse = iMouse.xy / iResolution.xy * 2.0 - 1.0;
        mouse.x *= iResolution.x / iResolution.y;
        float d = length(p - mouse);
        col += vec3(0.3, 0.5, 1.0) * smoothstep(0.2, 0.0, d);
    }

    fragColor = vec4(col, 1.0);
}
