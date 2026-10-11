// GazeShift compositor (ANO-10 copy, ANO-11 simulated blur). NOT YET BUNDLED OR COMPILED.
// Separate from CameraShaders.metal on purpose: the app compiles shader source at runtime, so an
// untested function in that file could break the working camera view. Integrate per
// docs/FLOW_INTEGRATION.md and verify on device before switching CameraView to `compositeFragment`.
#include <metal_stdlib>
using namespace metal;

struct CompositeVertex { float4 position [[position]]; float2 displayUV; };

// Must match CompositeUniformValues.GPU in GazeShiftFlow (six float2 then two uint, 56 bytes).
struct CompositeUniforms {
    float2 sourceOrigin;
    float2 destinationOrigin;
    float2 copySize;
    float2 blurCenter;
    float2 blurRadii;
    float2 blurKernel;
    uint copyEnabled;
    uint blurEnabled;
};

vertex CompositeVertex compositeVertex(uint id [[vertex_id]]) {
    const float2 positions[4] = {float2(-1, 1), float2(-1, -1), float2(1, 1), float2(1, -1)};
    const float2 uv[4] = {float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1)};
    return {float4(positions[id], 0, 1), uv[id]};
}

// Same mapping and colour conversion as cameraFragment: ORIGINAL camera pixels only.
static float3 sampleOriginal(float2 displayUV, texture2d<float> yTexture, texture2d<float> cbcrTexture,
                             float3x3 displayToRaw, sampler imageSampler) {
    float2 uv = (displayToRaw * float3(displayUV, 1)).xy;
    if (any(uv < 0) || any(uv > 1)) return float3(0);
    float y = yTexture.sample(imageSampler, uv).r;
    float2 cbcr = cbcrTexture.sample(imageSampler, uv).rg - 0.5;
    return float3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
}

// Copy step: a destination fragment reads the matching source location of the original frame.
static float2 copiedLocation(float2 displayUV, constant CompositeUniforms &u) {
    if (u.copyEnabled != 0 && all(displayUV >= u.destinationOrigin)
        && all(displayUV < u.destinationOrigin + u.copySize)) {
        return u.sourceOrigin + (displayUV - u.destinationOrigin);
    }
    return displayUV;
}

fragment float4 compositeFragment(CompositeVertex input [[stage_in]],
                                  texture2d<float> yTexture [[texture(0)]],
                                  texture2d<float> cbcrTexture [[texture(1)]],
                                  constant float3x3 &displayToRaw [[buffer(0)]],
                                  constant CompositeUniforms &u [[buffer(1)]]) {
    constexpr sampler imageSampler(filter::linear, address::clamp_to_edge);
    float2 uv = input.displayUV;
    if (u.blurEnabled != 0) {
        float2 q = (uv - u.blurCenter) / max(u.blurRadii, float2(1e-6));
        if (dot(q, q) <= 1.0) {
            // Blur LAST: average the copy-composited image, whose every tap still reads original pixels.
            float3 sum = float3(0);
            float weightSum = 0;
            for (int i = -3; i <= 3; i++) {
                for (int j = -3; j <= 3; j++) {
                    float2 tap = uv + float2(float(i), float(j)) / 3.0 * u.blurKernel;
                    float weight = exp(-0.5 * float(i * i + j * j) / 2.25);
                    sum += weight * sampleOriginal(copiedLocation(tap, u), yTexture, cbcrTexture, displayToRaw, imageSampler);
                    weightSum += weight;
                }
            }
            return float4(sum / weightSum, 1);
        }
    }
    return float4(sampleOriginal(copiedLocation(uv, u), yTexture, cbcrTexture, displayToRaw, imageSampler), 1);
}
