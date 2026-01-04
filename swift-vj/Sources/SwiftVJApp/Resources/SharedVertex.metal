// SharedVertex.metal - Vertex shader for all GLSL-converted fragment shaders

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen quad vertex shader
// Vertices: position (xy) + texcoord (zw)
vertex VertexOut vertex_fullscreen(uint vertexID [[vertex_id]],
                                   constant float4 *vertices [[buffer(0)]]) {
    VertexOut out;
    float4 v = vertices[vertexID];
    out.position = float4(v.xy, 0.0, 1.0);
    out.uv = v.zw;
    return out;
}
