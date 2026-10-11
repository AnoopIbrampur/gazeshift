#include <metal_stdlib>
using namespace metal;
struct CameraVertex { float4 position [[position]]; float2 displayUV; };
vertex CameraVertex cameraVertex(uint id [[vertex_id]]) {
    const float2 positions[4] = {float2(-1,1), float2(-1,-1), float2(1,1), float2(1,-1)};
    const float2 uv[4] = {float2(0,0), float2(0,1), float2(1,0), float2(1,1)};
    return {float4(positions[id], 0, 1), uv[id]};
}
fragment float4 cameraFragment(CameraVertex input [[stage_in]], texture2d<float> yTexture [[texture(0)]], texture2d<float> cbcrTexture [[texture(1)]], constant float3x3 &displayToRaw [[buffer(0)]]) {
    constexpr sampler imageSampler(filter::linear, address::clamp_to_edge);
    float2 uv = (displayToRaw * float3(input.displayUV, 1)).xy;
    if (any(uv < 0) || any(uv > 1)) return float4(0,0,0,1);
    float y = yTexture.sample(imageSampler, uv).r;
    float2 cbcr = cbcrTexture.sample(imageSampler, uv).rg - 0.5;
    // Full-range BT.601 YCbCr, matching Apple's ARKit camera-feed sample.
    float3 rgb = float3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
    return float4(rgb, 1);
}
