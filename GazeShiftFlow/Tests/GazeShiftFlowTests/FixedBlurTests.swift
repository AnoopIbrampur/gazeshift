import Testing
@testable import GazeShiftFlow

@Suite("Fixed blur backup")
struct FixedBlurTests {
    // Break caught: the backup accidentally enabling a copy or dropping the blur flag.
    @Test func fixedBlurIsBlurOnlyAtGivenNormalizedEllipse() {
        let gpu = CompositeUniformValues.fixedBlur(center: SIMD2(0.4, 0.35), radii: SIMD2(0.1, 0.05), kernel: SIMD2(0.07, 0.06))
        #expect(gpu.blurEnabled == 1 && gpu.copyEnabled == 0)
        #expect(gpu.blurCenter == SIMD2<Float>(0.4, 0.35))
        #expect(gpu.blurRadii == SIMD2<Float>(0.1, 0.05))
        #expect(gpu.copySize == .zero)
    }
}
