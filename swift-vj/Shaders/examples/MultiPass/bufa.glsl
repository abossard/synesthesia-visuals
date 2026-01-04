// MultiPass Example - Buffer A
// Generates a procedural pattern that will be post-processed by Image pass

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Create a procedural noise-like pattern
    vec2 p = uv * 10.0;
    float t = iTime;

    // Simple hash-based pattern
    vec2 i = floor(p);
    vec2 f = fract(p);

    // Smooth interpolation
    f = f * f * (3.0 - 2.0 * f);

    // Create animated cells
    float n = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 neighbor = vec2(float(dx), float(dy));
            vec2 point = vec2(
                sin(dot(i + neighbor, vec2(127.1, 311.7)) + t) * 0.5 + 0.5,
                sin(dot(i + neighbor, vec2(269.5, 183.3)) + t * 1.3) * 0.5 + 0.5
            );
            vec2 diff = neighbor + point - f;
            float d = length(diff);
            n += exp(-d * 3.0);
        }
    }

    // Color based on pattern
    vec3 col;
    col.r = sin(n * 3.14159 + t) * 0.5 + 0.5;
    col.g = sin(n * 3.14159 * 2.0 + t * 1.5) * 0.5 + 0.5;
    col.b = sin(n * 3.14159 * 0.5 + t * 0.7) * 0.5 + 0.5;

    fragColor = vec4(col, 1.0);
}
