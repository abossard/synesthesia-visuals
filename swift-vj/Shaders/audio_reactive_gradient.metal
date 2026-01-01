#include <metal_stdlib>
using namespace metal;

// Audio-reactive gradient shader
// Responds to bass, mid, and high frequencies

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Vertex shader - renders a fullscreen quad
vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    VertexOut out;
    
    // Fullscreen quad vertices (-1 to 1 in NDC)
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1), float2(1, -1), float2(1, 1)
    };
    
    out.position = float4(positions[vertexID], 0, 1);
    out.texCoord = positions[vertexID] * 0.5 + 0.5;  // Convert to 0-1 range
    
    return out;
}

// Fragment shader - audio-reactive gradient
fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant float &time [[buffer(0)]],
    constant float2 &resolution [[buffer(1)]],
    constant float &bassLevel [[buffer(2)]],
    constant float &midLevel [[buffer(3)]],
    constant float &highLevel [[buffer(4)]],
    constant float2 &mouse [[buffer(5)]]
) {
    float2 uv = in.texCoord;
    
    // Mouse influence on pattern
    float2 mouseOffset = (mouse - 0.5) * 0.3;
    uv += mouseOffset;
    
    // Audio-reactive parameters
    float bassPulse = 1.0 + bassLevel * 0.8;      // Bass drives overall pulse
    float midRotation = time * (0.3 + midLevel * 0.5);  // Mid drives rotation
    float highShimmer = 1.0 + highLevel * 0.3;    // High drives color shimmer
    
    // Create rotating gradient pattern
    float angle = atan2(uv.y - 0.5, uv.x - 0.5) + midRotation;
    float radius = length(uv - 0.5) * bassPulse;
    
    // Multi-frequency color mixing
    float3 color;
    color.r = 0.5 + 0.5 * cos(angle * 3.0 + time * highShimmer);
    color.g = 0.5 + 0.5 * cos(angle * 3.0 + time * highShimmer + 2.094);
    color.b = 0.5 + 0.5 * cos(angle * 3.0 + time * highShimmer + 4.189);
    
    // Add radial gradient influenced by bass
    float radialGrad = 1.0 - smoothstep(0.0, 0.7, radius);
    color *= mix(0.6, 1.0, radialGrad);
    
    // Bass hit flash (brief bright flash on strong bass)
    if (bassLevel > 0.7) {
        float flash = (bassLevel - 0.7) * 3.0;
        color += float3(flash * 0.3);
    }
    
    return float4(color, 1.0);
}
