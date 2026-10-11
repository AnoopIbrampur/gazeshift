import XCTest
import ImageIO
import Combine
import CoreVideo
import Metal
import simd
@testable import GazeShift

/// Exercises the bundled source and real simulator GPU compiler, not physical camera pixels.
final class CompositeShaderTests: XCTestCase {
    func testBundledCompositeShaderBuildsBGRA8RenderPipeline() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "A real Metal device is required")
        let url = try XCTUnwrap(Bundle.main.url(forResource: "CompositeShaders", withExtension: "metal"))
        let source = try String(contentsOf: url, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try XCTUnwrap(library.makeFunction(name: "compositeVertex"))
        descriptor.fragmentFunction = try XCTUnwrap(library.makeFunction(name: "compositeFragment"))
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        _ = try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

final class CapturePipelineTests: XCTestCase {
    // Break caught: world-space face pose, or the wrong multiplication order, is reported as camera-relative.
    func testFaceCameraPoseUsesSameFrameInverseCameraTimesFaceAndRejectsInvalidMatrices() throws {
        let camera = simd_float4x4(columns: (SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(1, 2, 3, 1)))
        let relative = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 0.5, 0.8660254, 0), SIMD4(0, -0.8660254, 0.5, 0), SIMD4(0.2, 0.3, -0.5, 1)))
        let pose = try XCTUnwrap(FaceCameraPose(cameraTransform: camera, faceTransform: camera * relative))
        XCTAssertEqual(pose.position.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(pose.position.y, 0.3, accuracy: 1e-6)
        XCTAssertEqual(pose.position.z, -0.5, accuracy: 1e-6)
        XCTAssertEqual(abs(pose.orientation.vector.x), 0.5, accuracy: 1e-6)
        XCTAssertEqual(abs(pose.orientation.vector.w), 0.8660254, accuracy: 1e-6)
        XCTAssertNil(FaceCameraPose(cameraTransform: simd_float4x4(), faceTransform: relative))
        var invalid = camera
        invalid.columns.0.x = .nan
        XCTAssertNil(FaceCameraPose(cameraTransform: invalid, faceTransform: relative))
    }

    // Break caught: non-frame emits inflate main frame totals, or counters leak through a generation reset.
    func testMainDeliveryCountersDeduplicateFrameIdentityAndResetWithGeneration() throws {
        var counter = CaptureDeliveryCounter()
        var value = CaptureSnapshot(sequence: 1, generation: 1, mode: .setupFront, status: .ready, support: nil,
                                    renderPacket: nil, eyes: nil, eyeIdentity: nil, hand: nil, handMessage: "fixture")
        value.frameDiagnostics = CaptureFrameDiagnostics(identity: identity(10), sourceFrameCount: 20)
        var delivered = counter.record(value, at: 10.1)
        XCTAssertEqual(delivered.mainDelivery?.acceptedSnapshots, 1)
        XCTAssertEqual(delivered.mainDelivery?.acceptedFrames, 1)
        XCTAssertEqual(try XCTUnwrap(delivered.mainDelivery?.estimatedCaptureToMainAge), 0.1, accuracy: 1e-6)
        delivered = counter.record(value, at: 10.2)
        XCTAssertEqual(delivered.mainDelivery?.acceptedSnapshots, 2)
        XCTAssertEqual(delivered.mainDelivery?.acceptedFrames, 1)
        value.frameDiagnostics = CaptureFrameDiagnostics(identity: identity(11), sourceFrameCount: 22)
        delivered = counter.record(value, at: 10.2)
        XCTAssertEqual(delivered.mainDelivery?.acceptedFrames, 2)
        let reset = CaptureSnapshot(sequence: 4, generation: 2, mode: .setupFront, status: .paused, support: nil,
                                    renderPacket: nil, eyes: nil, eyeIdentity: nil, hand: nil, handMessage: "fixture")
        delivered = counter.record(reset, at: 11)
        XCTAssertEqual(delivered.mainDelivery?.acceptedSnapshots, 1)
        XCTAssertEqual(delivered.mainDelivery?.acceptedFrames, 0)
        XCTAssertNil(delivered.mainDelivery?.estimatedCaptureToMainAge)
    }

    private func identity(_ timestamp: Double, receipt: Double = 10, generation: UInt64 = 1) -> FrameIdentity {
        FrameIdentity(generation: generation, captureTimestamp: timestamp, receivedAt: receipt)
    }
    private func eyes(tracked: Bool = true, x: Float = 0.1) -> EyeObservation {
        EyeObservation(lookAtPoint: SIMD3(x, 0.2, 1), leftEyeTranslation: SIMD3(-0.03, 0, 0), rightEyeTranslation: SIMD3(0.03, 0, 0), leftBlink: 0, rightBlink: 0, isTracked: tracked)
    }
    func testAgeIncludes250msBoundaryAndRejectsNegativeOrNonfinite() {
        XCTAssertTrue(identity(1).isFresh(at: 10.25))
        XCTAssertFalse(identity(1).isFresh(at: 10.250001))
        XCTAssertFalse(identity(1).isFresh(at: 9.99))
        XCTAssertFalse(identity(.nan).isFresh(at: 10))
        XCTAssertFalse(identity(1).isFresh(at: .infinity))
    }
    func testRecoveryNeedsThreeDistinctIncreasingFreshSamples() {
        var state = CaptureFreshness(generation: 1)
        state.acceptEyes(eyes(), identity: identity(1), now: 10)
        state.acceptEyes(eyes(), identity: identity(1), now: 10)
        XCTAssertEqual(state.recoveryCount, 1)
        state.acceptEyes(eyes(), identity: identity(2), now: 10)
        XCTAssertFalse(state.trackingAvailable)
        state.acceptEyes(eyes(), identity: identity(3), now: 10)
        XCTAssertTrue(state.trackingAvailable)
        state.acceptEyes(nil, identity: identity(4), now: 10)
        XCTAssertFalse(state.trackingAvailable)
        XCTAssertEqual(state.recoveryCount, 0)
    }
    func testInvalidEyesInvalidateRecoveryAndWrongGenerationCannotRecover() {
        for invalid in [eyes(tracked: false), eyes(x: .nan)] {
            var state = CaptureFreshness(generation: 1)
            state.acceptEyes(eyes(), identity: identity(1), now: 10)
            state.acceptEyes(invalid, identity: identity(2), now: 10)
            XCTAssertEqual(state.recoveryCount, 0)
        }
        var state = CaptureFreshness(generation: 2)
        state.acceptEyes(eyes(), identity: identity(1), now: 10)
        state.acceptEyes(eyes(), identity: identity(2, generation: 2), now: 10.251)
        XCTAssertEqual(state.recoveryCount, 0)
    }
    func testDuplicateFrameCannotRefreshIndependentWatchdog() {
        var state = CaptureFreshness(generation: 1)
        XCTAssertTrue(state.acceptScene(identity(1), now: 10))
        XCTAssertFalse(state.acceptScene(identity(1, receipt: 10.2), now: 10.2))
        XCTAssertFalse(state.expireScene(at: 10.25))
        XCTAssertTrue(state.expireScene(at: 10.251))
        XCTAssertFalse(state.acceptScene(identity(0, receipt: 10.3), now: 10.3))
        XCTAssertTrue(state.acceptScene(identity(2, receipt: 10.3), now: 10.3))
    }
    func testNewestQueueExecutesAThenCAndClearDoesNotReleaseA() {
        var queue = NewestWorkQueue<String>()
        XCTAssertEqual(queue.offer("A"), "A")
        XCTAssertNil(queue.offer("B"))
        XCTAssertNil(queue.offer("C"))
        XCTAssertEqual(queue.complete(), "C")
        XCTAssertNil(queue.complete())
        XCTAssertEqual(queue.offer("A"), "A")
        queue.clearPending()
        XCTAssertNil(queue.offer("new generation"))
        XCTAssertEqual(queue.inFlight, "A")
        XCTAssertEqual(queue.complete(), "new generation")
    }
    func testAsymmetricPortraitRotationAndDeliberateMirrorOnce() throws {
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        let unmirrored = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300, height: 500), displayTransform: transform, orientation: .right, mirrored: false))
        let mirrored = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300, height: 500), displayTransform: transform, orientation: .right, mirrored: true))
        assertPoint(unmirrored.visionToDisplay(CGPoint(x: 0.2, y: 0.7)), CGPoint(x: 0.2, y: 0.3))
        assertPoint(mirrored.visionToDisplay(CGPoint(x: 0.2, y: 0.7)), CGPoint(x: 0.8, y: 0.3))
    }
    func testEXIFInverseAllOrientationsAndCropRoundTrip() throws {
        let inputs: [(CGImagePropertyOrientation, CGPoint)] = [(.up, CGPoint(x: 0.2,y: 0.3)), (.upMirrored, CGPoint(x: 0.8,y: 0.3)), (.down, CGPoint(x: 0.8,y: 0.7)), (.downMirrored, CGPoint(x: 0.2,y: 0.7)), (.leftMirrored, CGPoint(x: 0.3,y: 0.2)), (.right, CGPoint(x: 0.3,y: 0.8)), (.rightMirrored, CGPoint(x: 0.7,y: 0.8)), (.left, CGPoint(x: 0.7,y: 0.2))]
        for (orientation, expectedRaw) in inputs {
            let geometry = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300,height: 500), displayTransform: .identity, orientation: orientation, mirrored: false))
            assertPoint(geometry.visionToDisplay(CGPoint(x: 0.2,y: 0.7)), expectedRaw)
        }
        let geometry = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300,height: 500), displayTransform: CGAffineTransform(a: 1.4,b: 0,c: 0,d: 1.8,tx: -0.2,ty: -0.4), orientation: .up, mirrored: true))
        let display = geometry.visionToDisplay(CGPoint(x: 0.2,y: 0.7))
        assertPoint(display, CGPoint(x: 0.92,y: 0.14))
        assertPoint(geometry.displayToRaw(display), CGPoint(x: 0.2,y: 0.3))
    }
    func testInvalidGeometryRejected() {
        XCTAssertNil(DisplayGeometry(viewport: .zero, displayTransform: .identity, orientation: .up, mirrored: false))
        XCTAssertNil(DisplayGeometry(viewport: CGSize(width: 1,height: 1), displayTransform: CGAffineTransform(scaleX: 0,y: 1), orientation: .up, mirrored: false))
    }
    func testSimulatorSnapshotContainsNoInventedSensorsOrScene() {
        let snapshot = CaptureSnapshot.simulator
        XCTAssertEqual(snapshot.status, .simulator)
        XCTAssertNil(snapshot.renderPacket)
        XCTAssertNil(snapshot.eyes)
        XCTAssertNil(snapshot.eyeIdentity)
        XCTAssertNil(snapshot.hand)
    }
    func testDelayedCallbackAgeUsesElapsedCaptureClockWithoutAssumingEpochs() throws {
        var clock = CaptureClock()
        let first = try XCTUnwrap(clock.identity(generation: 1, captureTimestamp: 5000, receivedAt: 10))
        XCTAssertTrue(first.isFresh(at: 10))
        let queued = try XCTUnwrap(clock.identity(generation: 1, captureTimestamp: 5000.033, receivedAt: 10.4))
        XCTAssertFalse(queued.isFresh(at: 10.4))
        XCTAssertNil(clock.identity(generation: 1, captureTimestamp: .nan, receivedAt: 10.5))
    }
    func testSwitchRejectsOldInFlightCompletionAndOlderCurrentResults() {
        var gate = HandResultFreshness(generation: 2)
        XCTAssertFalse(gate.accept(identity(1, generation: 1), now: 10))
        XCTAssertTrue(gate.accept(identity(3, generation: 2), now: 10))
        XCTAssertFalse(gate.accept(identity(2, generation: 2), now: 10))
        XCTAssertFalse(gate.accept(identity(3, generation: 2), now: 10))
        XCTAssertFalse(gate.accept(identity(4, generation: 2), now: 10.251))
    }
    @MainActor
    func testSimulatorControlsNeverPublishRealOrSimulatedSensorInput() async {
        #if targetEnvironment(simulator)
        let model = CaptureModel()
        let updated = expectation(description: "Simulator rear selection published")
        var received: [CaptureSnapshot] = []
        let subscription = model.$snapshot.sink { snapshot in
            received.append(snapshot)
            if snapshot.mode == .liveRear && snapshot.status == .simulator { updated.fulfill() }
        }
        model.layout(CGSize(width: 300, height: 500), scale: 3)
        model.start(.liveRear)
        await fulfillment(of: [updated], timeout: 3)
        for snapshot in received {
            XCTAssertEqual(snapshot.status, .simulator)
            XCTAssertNil(snapshot.renderPacket)
            XCTAssertNil(snapshot.eyes)
            XCTAssertNil(snapshot.hand)
        }
        subscription.cancel()
        model.stop()
        #endif
    }
    func testDelayedSourceWatchdogUsesCaptureAgeRatherThanCallbackReceipt() {
        var state = CaptureFreshness(generation: 1)
        let delayed = FrameIdentity(generation: 1, captureTimestamp: 50, receivedAt: 10.2, estimatedCaptureAt: 10)
        XCTAssertTrue(state.acceptScene(delayed, now: 10.2))
        XCTAssertTrue(state.expireScene(at: 10.251))
    }
    func testDelayedDisplayUpdateCannotRestoreStaleSceneEyesOrCursor() throws {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &image), kCVReturnSuccess)
        let geometry = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300, height: 500), displayTransform: .identity, orientation: .up, mirrored: false))
        let id = identity(1)
        let packet = RenderPacket(identity: id, image: try XCTUnwrap(image), geometry: geometry, mode: .setupFront)
        let hand = HandObservation(identity: id, indexTip: CGPoint(x: 0.2,y: 0.3), thumbTip: CGPoint(x: 0.3,y: 0.4), indexConfidence: 1, thumbConfidence: 1)
        var snapshot = CaptureSnapshot(sequence: 1, generation: 1, mode: .setupFront, status: .ready, support: nil, renderPacket: packet, eyes: eyes(), eyeIdentity: id, hand: hand, handMessage: "active")
        snapshot.frameDiagnostics = CaptureFrameDiagnostics(identity: id, sourceFrameCount: 1)
        let delayed = snapshot.forDisplay(at: 10.251)
        XCTAssertEqual(delayed.status, .sceneUnavailable)
        XCTAssertNil(delayed.renderPacket)
        XCTAssertNil(delayed.eyes)
        XCTAssertNil(delayed.eyeIdentity)
        XCTAssertNil(delayed.hand)
        XCTAssertEqual(delayed.frameDiagnostics?.identity, id, "Stale diagnostics remain observational; stale sensor input remains removed")
        snapshot.frameDiagnostics = CaptureFrameDiagnostics(identity: identity(2), sourceFrameCount: 2)
        XCTAssertNil(snapshot.forDisplay(at: 10).frameDiagnostics, "Different-frame metadata must not attach to these pixels")
        snapshot.frameDiagnostics = CaptureFrameDiagnostics(identity: identity(1, generation: 2), sourceFrameCount: 1)
        XCTAssertNil(snapshot.forDisplay(at: 10).frameDiagnostics, "Different-generation metadata must not attach to these pixels")
    }
    func testRawInvalidEyeMetadataSurvivesOnlyForFreshEvaluation() throws {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &image), kCVReturnSuccess)
        let geometry = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300, height: 500), displayTransform: .identity, orientation: .up, mirrored: false))
        let id = identity(1)
        let packet = RenderPacket(identity: id, image: try XCTUnwrap(image), geometry: geometry, mode: .setupFront)
        let raw = eyes(tracked: false)
        let snapshot = CaptureSnapshot(sequence: 1, generation: 1, mode: .setupFront, status: .trackingUnavailable,
                                       support: nil, renderPacket: packet, eyes: nil, eyeIdentity: nil, hand: nil,
                                       handMessage: "Hand unavailable", rawEyes: raw, rawEyeIdentity: id)
        let fresh = snapshot.forDisplay(at: 10.1)
        XCTAssertNil(fresh.eyes)
        XCTAssertEqual(fresh.rawEyes?.isTracked, false)
        XCTAssertEqual(fresh.rawEyeIdentity, id)
        let stale = snapshot.forDisplay(at: 10.251)
        XCTAssertNil(stale.rawEyes)
        XCTAssertNil(stale.rawEyeIdentity)
    }
    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.000001, file: file, line: line)
    }
}
