#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;
using namespace realitykit;

struct WaterUniforms {
    float time;
    float amplitude;
    float frequency;
    float causticTint;
};

[[geometry_modifier]]
void waterGeometry(realitykit::geometry_parameters params) {
    const device WaterUniforms& uniforms = params.uniforms().as<WaterUniforms>();
    float2 uv = params.geometry().uv0();
    float wave = sin((uv.x + uniforms.time) * uniforms.frequency) * cos((uv.y + uniforms.time) * uniforms.frequency);
    float offset = wave * uniforms.amplitude;
    params.geometry().position().y += offset;
}

[[surface]]
void waterSurface(realitykit::surface_parameters params) {
    const device WaterUniforms& uniforms = params.uniforms().as<WaterUniforms>();
    float3 base = float3(0.02, 0.18, 0.35);
    float3 caustic = float3(0.0, 0.4, 0.6) * uniforms.causticTint;
    params.surface().base_color = float4(base + caustic, 1.0);
    params.surface().roughness = 0.2;
    params.surface().metallic = 0.0;
}

kernel void postProcessKernel(
    texture2d<float, access::read> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destinationTexture [[texture(1)]],
    constant float& bloomIntensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destinationTexture.get_width() || gid.y >= destinationTexture.get_height()) {
        return;
    }
    float4 color = sourceTexture.read(gid);
    float glow = max(color.r, max(color.g, color.b));
    float boost = 1.0 + bloomIntensity * smoothstep(0.2, 1.0, glow);
    destinationTexture.write(float4(color.rgb * boost, color.a), gid);
}
