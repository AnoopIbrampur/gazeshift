import Testing
import GazeShiftCore
@testable import GazeShiftFlow

@Suite("Comparison composition (fixtures)")
struct CompositionTests {
    static let gaze = Fixture.fixation
    static let offset = ScreenPoint(x: 100, y: 150)

    static func plan(_ mode: ViewMode, gaze: ScreenPoint? = gaze, offset: ScreenPoint = offset) -> CompositionPlan {
        let geometry = Fixture.geometry(.rearLive)
        return CompositionPlanner.plan(
            mode: mode, region: Fixture.rearRegion(), gaze: gaze, geometry: geometry, userOffset: offset,
            liveMargin: LivePlacementMargin(p90ErrorPoints: 10, geometry: geometry, validated: true),
            cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: 300, height: 400))
    }

    @Test func originalHasNoAdaptiveLayersButKeepsLabel() {
        let plan = Self.plan(.comparison(.original))
        #expect(plan.isOriginalOnly)
        #expect(plan.simulationLabel == CompositionPlan.simulationLabelText)
    }

    // Break caught: normal Live assist showing simulated blur.
    @Test func liveCopiesWithoutBlurOrLabel() throws {
        let plan = Self.plan(.live)
        let copy = try #require(plan.copy)
        #expect(plan.blur == nil)
        #expect(plan.simulationLabel == nil)
        #expect(copy.source == ScreenRect(x: 90, y: 120, width: 60, height: 40))
        #expect(copy.destination == ScreenRect(x: 190, y: 270, width: 60, height: 40))
    }

    @Test func simulatedBlurMasksRegionAtGazePlusOffsetWithoutCopy() throws {
        let plan = Self.plan(.comparison(.simulatedBlur))
        let blur = try #require(plan.blur)
        #expect(plan.copy == nil)
        #expect(abs(blur.center.x - 120) < 1e-9 && abs(blur.center.y - 140) < 1e-9)
        #expect(abs(blur.radii.x - 30) < 1e-9 && abs(blur.radii.y - 20) < 1e-9)
    }

    // Break caught: mask and patch tracking different points, or copy sampling outside the masked region.
    @Test func blurPlusCopySharesOneEllipse() throws {
        let plan = Self.plan(.comparison(.simulatedBlurPlusCopy))
        let copy = try #require(plan.copy)
        let blur = try #require(plan.blur)
        #expect(copy.source.x == blur.center.x - blur.radii.x)
        #expect(copy.source.y == blur.center.y - blur.radii.y)
        #expect(plan.simulationLabel == CompositionPlan.simulationLabelText)
    }

    // Break caught: stale patch or blur surviving tracking loss.
    @Test func lostGazeRemovesEveryAdaptiveLayer() {
        for mode in [ViewMode.live, .comparison(.simulatedBlur), .comparison(.simulatedBlurPlusCopy)] {
            let plan = Self.plan(mode, gaze: nil)
            #expect(plan.isOriginalOnly)
            #expect(plan.statusText == CompositionPlan.trackingUnavailableText)
        }
    }

    // Break caught: clamping or shrinking an overlapping destination instead of rejecting.
    @Test func overlappingDestinationShowsOriginalWithPlacementStatus() {
        for mode in [ViewMode.live, .comparison(.simulatedBlurPlusCopy)] {
            let plan = Self.plan(mode, offset: ScreenPoint(x: 10, y: 0))
            #expect(plan.isOriginalOnly)
            #expect(plan.statusText == "No valid placement — original view")
        }
    }

    @Test func uniformsAreNormalizedDisplayUV() {
        let plan = Self.plan(.comparison(.simulatedBlurPlusCopy))
        let uniforms = CompositeUniformValues(plan: plan, geometry: Fixture.geometry(.rearLive))
        #expect(uniforms.copyEnabled && uniforms.blurEnabled)
        #expect(uniforms.sourceOrigin == SIMD2<Float>(0.3, 0.3))
        #expect(uniforms.destinationOrigin == SIMD2<Float>(Float(190.0 / 300), Float(270.0 / 400)))
        #expect(uniforms.copySize == SIMD2<Float>(0.2, 0.1))
        #expect(uniforms.blurCenter == SIMD2<Float>(0.4, 0.35))
    }

    // Break caught: Swift/Metal struct layout drift silently scrambling shader inputs.
    @Test func gpuUniformLayoutMatchesMetalStruct() {
        #expect(MemoryLayout<CompositeUniformValues.GPU>.size == 56)
        #expect(MemoryLayout<CompositeUniformValues.GPU>.stride == 56)
        #expect(MemoryLayout<CompositeUniformValues.GPU>.offset(of: \.copyEnabled) == 48)
        let original = CompositeUniformValues(plan: Self.plan(.comparison(.original)), geometry: Fixture.geometry(.rearLive)).gpu
        #expect(original.copyEnabled == 0 && original.blurEnabled == 0)
    }
}
