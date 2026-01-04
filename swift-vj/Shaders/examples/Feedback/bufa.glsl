// Feedback Example - Buffer A (with ping-pong)
// Reads its own previous frame (iChannel0) to create trail/persistence effects

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Sample previous frame with slight offset for motion blur
    vec2 offset = vec2(0.002, 0.001) * sin(iTime);
    vec4 prev = texture(iChannel0, uv + offset);

    // Fade previous frame (creates trails)
    prev *= 0.97;

    // Create new content: moving particle
    vec2 p = uv * 2.0 - 1.0;
    p.x *= iResolution.x / iResolution.y;

    // Particle position (moving in a figure-8)
    float t = iTime * 2.0;
    vec2 particlePos = vec2(
        sin(t) * 0.5,
        sin(t * 2.0) * 0.3
    );

    // Draw particle
    float d = length(p - particlePos);
    float particle = smoothstep(0.1, 0.0, d);

    // Particle color cycles
    vec3 particleColor = vec3(
        sin(iTime * 1.0) * 0.5 + 0.5,
        sin(iTime * 1.3 + 2.0) * 0.5 + 0.5,
        sin(iTime * 0.7 + 4.0) * 0.5 + 0.5
    );

    // Mouse interaction: add particles at mouse position
    float mouseParticle = 0.0;
    if (iMouse.z > 0.0) {
        vec2 mouse = iMouse.xy / iResolution.xy * 2.0 - 1.0;
        mouse.x *= iResolution.x / iResolution.y;
        mouseParticle = smoothstep(0.15, 0.0, length(p - mouse));
    }

    // Combine previous frame with new content
    vec3 col = prev.rgb;
    col += particleColor * particle;
    col += vec3(1.0, 0.8, 0.6) * mouseParticle;

    // Prevent overflow
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col, 1.0);
}
