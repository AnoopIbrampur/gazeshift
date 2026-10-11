import XCTest
import Combine
import CoreVideo
import GazeShiftCore
@testable import GazeShift

final class GazeSessionTests: XCTestCase {
    func testNoMarkerBeforeNineTargetCalibrationAndCaptureUsesHostClock() throws {
        var session = configured()
        session.receive(try snapshot(x: 0.5, y: 0.5, host: 10, source: 5000), now: 10)
        XCTAssertNil(session.marker(at: 10))
        session.startCalibration()
        XCTAssertEqual(session.target?.normalized, ScreenPoint(x: 0.15, y: 0.15))
        session.targetPresented(at: 10)
        session.receive(try snapshot(x: 0.15, y: 0.15, host: 10.6, source: 5000.6), now: 10.6)
        XCTAssertEqual(session.currentTrainingCount, 1)
        session.receive(try snapshot(x: 0.15, y: 0.15, host: 10.61, source: 5000.6), now: 10.61)
        XCTAssertEqual(session.currentTrainingCount, 1, "Duplicate source frames cannot add calibration samples")
        session.tick(now: 11.5)
        XCTAssertNil(session.calibration)
        XCTAssertEqual(session.trainingIndex, 0, "Insufficient target repeats instead of making up samples")
        XCTAssertTrue(session.trainingFeatureSummaries.isEmpty)
    }

    func testFittedMarkerNeedsThreeDistinctSamplesAndClearsForBlinkLossStaleAndOffscreen() throws {
        var session = try calibrated()
        XCTAssertEqual(session.displayState(at: 30), .sceneUnavailable)
        for index in 0..<3 {
            let time = 30 + Double(index) * 0.02
            session.receive(try snapshot(x: 0.25, y: 0.75, host: time), now: time)
        }
        let point = try XCTUnwrap(session.marker(at: 30.04))
        XCTAssertEqual(point.x, 75, accuracy: 0.001)
        XCTAssertEqual(point.y, 300, accuracy: 0.001)
        XCTAssertEqual(session.displayState(at: 30.04), .active)
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.05, blink: 0.6), now: 30.05)
        XCTAssertNil(session.marker(at: 30.05))
        XCTAssertEqual(session.displayState(at: 30.05), .unavailable)
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.06), now: 30.06)
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.06), now: 30.07)
        XCTAssertNil(session.marker(at: 30.07))
        XCTAssertEqual(session.displayState(at: 30.07), .recovering(1))
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.08), now: 30.08)
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.09), now: 30.09)
        XCTAssertNotNil(session.marker(at: 30.09))
        XCTAssertNil(session.marker(at: 30.341))
        session.tick(now: 30.341)
        session.receive(try snapshot(x: -0.2, y: 0.75, host: 30.35), now: 30.35)
        XCTAssertNil(session.marker(at: 30.35), "Offscreen output must not clamp to an edge")
        XCTAssertEqual(session.displayState(at: 30.35), .outsideView)
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.36, tracked: false), now: 30.36)
        XCTAssertNil(session.marker(at: 30.36))
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.37, blink: nil), now: 30.37)
        XCTAssertNil(session.marker(at: 30.37))
    }

    func testGenerationModeAndViewportChangesDiscardFitAndEvaluation() throws {
        for change in 0..<4 {
            var session = try calibrated()
            session.startEvaluation()
            session.configure(size: CGSize(width: change == 0 ? 301 : 300, height: 400),
                              scale: change == 1 ? 2 : 3,
                              mode: change == 2 ? .setupFront : .liveRear,
                              generation: change == 3 ? 2 : 1)
            XCTAssertNil(session.calibration)
            XCTAssertNil(session.report)
            XCTAssertNil(session.target)
            XCTAssertEqual(session.phase, .uncalibrated)
            XCTAssertTrue(session.trainingFeatureSummaries.isEmpty)
        }
    }

    // Break caught: raw tracking stays ready off-screen, so it cannot authorize immediate calibrated recovery.
    func testOffscreenLossRequiresThreeDistinctInViewPredictionsBeforeRecovery() throws {
        var session = try calibrated()
        for index in 0..<3 {
            let time = 30 + Double(index) * 0.02
            session.receive(try snapshot(x: 0.25, y: 0.75, host: time), now: time)
        }
        XCTAssertNotNil(session.marker(at: 30.04))
        session.receive(try snapshot(x: -0.2, y: 0.75, host: 30.05), now: 30.05)
        XCTAssertEqual(session.displayState(at: 30.05), .outsideView)
        XCTAssertNil(session.marker(at: 30.05))

        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.06), now: 30.06)
        XCTAssertEqual(session.displayState(at: 30.06), .recovering(1))
        XCTAssertNil(session.marker(at: 30.06))
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.06), now: 30.065)
        XCTAssertEqual(session.displayState(at: 30.065), .recovering(1))
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.07), now: 30.07)
        XCTAssertEqual(session.displayState(at: 30.07), .recovering(2))
        XCTAssertNil(session.marker(at: 30.07))
        session.receive(try snapshot(x: 0.25, y: 0.75, host: 30.08), now: 30.08)
        XCTAssertEqual(session.displayState(at: 30.08), .active)
        XCTAssertNotNil(session.marker(at: 30.08))
    }

    func testMovingViewportWithoutResizingStillInvalidatesPhysicalScreenFit() throws {
        var session = try calibrated()
        session.configure(size: CGSize(width: 300, height: 400), scale: 3, mode: .liveRear,
                          generation: 1, origin: CGPoint(x: 0, y: 20))
        XCTAssertNil(session.calibration)
        XCTAssertEqual(session.phase, .uncalibrated)
    }

    func testRawInvalidEyesProduceSpecificHeldOutReasonsWithoutDisplayMarkers() throws {
        var session = try calibrated()
        session.startEvaluation()
        session.targetPresented(at: 30)
        session.receive(try snapshot(x: 0.25, y: 0.25, host: 30.525, blink: 0.8), now: 30.525)
        session.tick(now: 30.525)
        session.receive(try snapshot(x: 0.25, y: 0.25, host: 30.575, tracked: false), now: 30.575)
        session.tick(now: 30.575)
        session.receive(try snapshot(x: 0.25, y: 0.25, host: 30.625, blink: nil), now: 30.625)
        session.tick(now: 30.625)
        session.tick(now: 31.5)
        let result = try XCTUnwrap(session.completedWindows.first)
        XCTAssertEqual(result.rejectionCounts[.closedEyes], 1)
        XCTAssertEqual(result.rejectionCounts[.untracked], 1)
        XCTAssertEqual(result.rejectionCounts[.missingQuality], 1)
        XCTAssertEqual(result.rejectedSlots, 20)
    }

    func testClosedEyesMissingSceneAndWrongGenerationCannotSupplyTraining() throws {
        var session = configured()
        session.startCalibration()
        session.targetPresented(at: 10)
        let values = [
            try snapshot(x: 0.15, y: 0.15, host: 10.6, blink: 0.6),
            try snapshot(x: 0.15, y: 0.15, host: 10.7, blink: nil),
            try snapshot(x: 0.15, y: 0.15, host: 10.8, scene: false),
            try snapshot(x: 0.15, y: 0.15, host: 10.9, generation: 2)
        ]
        for value in values { session.receive(value, now: value.eyeIdentity!.receivedAt) }
        XCTAssertEqual(session.currentTrainingCount, 0)
    }

    func testCompleteTimedProtocolRequiresExplicitEyeOnlyReportAndKeepsCenterSeparate() throws {
        var session = try calibrated()
        try evaluate(&session, offscreen: false)
        let report = try XCTUnwrap(session.report)
        XCTAssertTrue(report.passesNumericalGate)
        XCTAssertTrue(report.passesProtocolGate)
        XCTAssertFalse(report.passesCompleteGate)
        XCTAssertEqual(report.novelWindows.count, 8)
        XCTAssertEqual(report.centerControls.count, 2)
        XCTAssertEqual(report.overallValidPredictions, 160)
        XCTAssertEqual(report.overallRejectedSlots, 0)
        session.recordEyeOnly(.observedPass)
        XCTAssertTrue(try XCTUnwrap(session.report).passesCompleteGate)
        session.recordEyeOnly(.observedFail)
        XCTAssertFalse(try XCTUnwrap(session.report).passesCompleteGate)
    }

    func testOffscreenPredictionsAreScoredRatherThanRemovedByMarkerFilter() throws {
        var session = try calibrated()
        try evaluate(&session, offscreen: true)
        let report = try XCTUnwrap(session.report)
        XCTAssertEqual(report.overallValidPredictions, 160)
        XCTAssertEqual(report.overallRejectedSlots, 0)
        XCTAssertGreaterThan(try XCTUnwrap(report.overallErrors).medianPoints, 300)
        XCTAssertFalse(report.passesNumericalGate)
    }

    func testLateSchedulerDoesNotBackfillOrExtendEvaluationWindows() throws {
        var session = try calibrated()
        session.startEvaluation()
        session.targetPresented(at: 30)
        session.receive(try snapshot(x: 0.25, y: 0.25, host: 31.6), now: 31.6)
        session.tick(now: 31.6)
        XCTAssertEqual(session.completedWindows.count, 1)
        XCTAssertEqual(session.completedWindows[0].expectedSlots, 20)
        XCTAssertEqual(session.completedWindows[0].validPredictions, 0)
        XCTAssertEqual(session.completedWindows[0].rejectedSlots, 20)
        XCTAssertEqual(session.completedWindows[0].rejectionCounts[.missedSchedule], 20)
        XCTAssertEqual(session.completedWindows[0].endsAt, 31.5)
    }

    // Break caught: summaries include a failed capture or survive a new calibration/setup.
    func testTrainingFeatureSummariesFollowCompletedTargetsAndResetWithCalibration() throws {
        var session = try calibrated()
        XCTAssertEqual(session.trainingFeatureSummaries.count, 9)
        let coordinates = [0.15, 0.5, 0.85]
        for (index, value) in session.trainingFeatureSummaries.enumerated() {
            let summary = try XCTUnwrap(value)
            XCTAssertEqual(summary.horizontalMean, coordinates[index % 3], accuracy: 1e-7)
            XCTAssertEqual(summary.verticalMean, coordinates[index / 3], accuracy: 1e-7)
            XCTAssertEqual(summary.horizontalPopulationSD, 0, accuracy: 1e-12)
            XCTAssertEqual(summary.verticalPopulationSD, 0, accuracy: 1e-12)
        }
        session.startEvaluation()
        XCTAssertEqual(session.trainingFeatureSummaries.count, 9)
        session.cancel()
        session.startCalibration()
        XCTAssertTrue(session.trainingFeatureSummaries.isEmpty)
        session.targetPresented(at: 60)
        session.receive(try snapshot(x: -9, y: -9, host: 60.6), now: 60.6)
        session.tick(now: 61.5)
        XCTAssertTrue(session.trainingFeatureSummaries.isEmpty, "An insufficient capture has no completed-target summary")
        session.targetPresented(at: 62)
        for index in 0..<30 {
            let time = 62.51 + Double(index) * 0.03
            session.receive(try snapshot(x: 0.75, y: 0.8, host: time), now: time)
        }
        session.tick(now: 63.5)
        XCTAssertEqual(session.trainingFeatureSummaries.count, 1)
        let repeated = try XCTUnwrap(session.trainingFeatureSummaries[0])
        XCTAssertEqual(repeated.horizontalMean, 0.75, accuracy: 1e-7)
        XCTAssertEqual(repeated.verticalMean, 0.8, accuracy: 1e-7)
        session.invalidate("Stopped")
        XCTAssertTrue(session.trainingFeatureSummaries.isEmpty)
    }

    // Break caught: the shared/exported report omits signed or raw-feature diagnostics or invents empty values.
    func testReportExportsObservationalDiagnosticsAndUnavailableEmptyWindows() throws {
        var session = try calibrated()
        try evaluate(&session, offscreen: true)
        let text = session.reportText
        XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.hasPrefix("Training target ") }.count, 9)
        XCTAssertTrue(text.contains("signed median dx -375.0pt"))
        XCTAssertTrue(text.contains("+right/+down"))
        XCTAssertTrue(text.contains("raw h mean -1"))
        XCTAssertTrue(text.contains("population SD"))
        XCTAssertTrue(text.contains("Observational diagnostics"))
        session.recordEyeOnly(.observedFail)
        XCTAssertTrue(session.reportText.contains("signed median dx -375.0pt"))

        session.startEvaluation()
        for window in 0..<10 {
            let start = 60 + Double(window) * 2
            session.targetPresented(at: start)
            session.tick(now: start + 1.5)
        }
        XCTAssertTrue(session.reportText.contains("signed median dx/dy unavailable"))
        XCTAssertTrue(session.reportText.contains("raw eye features unavailable"))
        XCTAssertFalse(try XCTUnwrap(session.report).passesNumericalGate)
    }

    private func configured() -> GazeSession {
        var session = GazeSession()
        session.configure(size: CGSize(width: 300, height: 400), scale: 3, mode: .liveRear, generation: 1)
        return session
    }

    private func calibrated() throws -> GazeSession {
        var session = configured()
        session.startCalibration()
        for target in 0..<9 {
            let start = 10 + Double(target) * 2
            let point = try XCTUnwrap(session.target).normalized
            session.targetPresented(at: start)
            for index in 0..<30 {
                let time = start + 0.51 + Double(index) * 0.03
                session.receive(try snapshot(x: point.x, y: point.y, host: time), now: time)
            }
            session.tick(now: start + 1.5)
        }
        XCTAssertNotNil(session.calibration)
        XCTAssertEqual(session.trainingCounts, Array(repeating: 30, count: 9))
        return session
    }

    private func evaluate(_ session: inout GazeSession, offscreen: Bool) throws {
        session.startEvaluation()
        for window in 0..<10 {
            let start = 30 + Double(window) * 2
            let target = try XCTUnwrap(session.target).normalized
            session.targetPresented(at: start)
            XCTAssertNil(session.marker(at: start), "No feedback marker while measuring a target")
            for slot in 0..<20 {
                let time = start + 0.525 + Double(slot) * 0.05
                session.receive(try snapshot(x: offscreen ? -1 : target.x, y: target.y, host: time), now: time)
                session.tick(now: time)
            }
            session.tick(now: start + 1.5)
        }
    }

    private func snapshot(x: Double, y: Double, host: Double, source: Double? = nil,
                          blink: Float? = 0, tracked: Bool = true, scene: Bool = true,
                          generation: UInt64 = 1) throws -> CaptureSnapshot {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &image), kCVReturnSuccess)
        let identity = FrameIdentity(generation: generation, captureTimestamp: source ?? host + 5000,
                                     receivedAt: host, estimatedCaptureAt: host)
        let geometry = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300, height: 400), displayTransform: .identity, orientation: .right, mirrored: false))
        let packet = RenderPacket(identity: identity, image: try XCTUnwrap(image), geometry: geometry, mode: .liveRear)
        let eyes = EyeObservation(lookAtPoint: SIMD3(Float(x), Float(y), 1), leftEyeTranslation: SIMD3(-0.03, 0, 0),
                                  rightEyeTranslation: SIMD3(0.03, 0, 0), leftBlink: blink, rightBlink: blink, isTracked: tracked)
        return CaptureSnapshot(sequence: 1, generation: generation, mode: .liveRear, status: .ready,
                               support: nil, renderPacket: scene ? packet : nil, eyes: eyes, eyeIdentity: identity,
                               hand: nil, handMessage: "Hand unavailable", rawEyes: eyes, rawEyeIdentity: identity)
    }
}

/// Synthetic adapter fixtures exercise the actual app model; they do not prove sensor behavior.
@MainActor
final class AirTraceModelTests: XCTestCase {
    private let events = PassthroughSubject<CaptureEvent, Never>()
    private var gaze = GazeSession()

    func testNilHandCompletionClearsStrokeBeforeWatchdog() throws {
        let model = try startedModel()
        sendFrame(0)
        XCTAssertEqual(model.flow?.state, .tracing)
        sendFrame(1, hasHand: false)
        sendFrame(2)
        XCTAssertEqual(model.flow?.state, .invalid(.missingPair))
        XCTAssertTrue(model.flow?.rawTrace.isEmpty == true)
    }

    func testVisionErrorCompletionCannotBeBridgedByNextGoodFrame() throws {
        let model = try startedModel()
        sendFrame(0)
        let identity = FrameIdentity(generation: 1, captureTimestamp: 7000.02,
                                     receivedAt: ProcessInfo.processInfo.systemUptime)
        events.send(.eyes(eyes(x: 0.5, y: 0.5), identity: identity, mode: .setupFront))
        events.send(.hand(.failure(NSError(domain: "VisionFixture", code: 1)), identity: identity, mode: .setupFront))
        sendFrame(2)
        XCTAssertEqual(model.flow?.state, .invalid(.missingPair))
        XCTAssertTrue(model.flow?.rawTrace.isEmpty == true)
    }

    func testMissingRawEyesCannotBeBridgedByNextGoodFrame() throws {
        let model = try startedModel()
        sendFrame(0)
        sendFrame(1, hasHand: false, hasRawIdentity: false)
        sendFrame(2)
        XCTAssertEqual(model.flow?.state, .invalid(.invalidGaze))
        XCTAssertTrue(model.flow?.rawTrace.isEmpty == true)
    }

    func testBadEyesOnFrameSkippedByVisionClearStroke() throws {
        let model = try startedModel()
        sendFrame(0)
        let identity = FrameIdentity(generation: 1, captureTimestamp: 7000.02,
                                     receivedAt: ProcessInfo.processInfo.systemUptime)
        events.send(.eyes(nil, identity: identity, mode: .setupFront))
        sendFrame(2)
        XCTAssertEqual(model.flow?.state, .invalid(.invalidGaze))
        XCTAssertTrue(model.flow?.rawTrace.isEmpty == true)
    }

    func testRevokedCalibrationApprovalClearsStrokeAndBlocksRedo() throws {
        let model = try startedModel()
        sendFrame(0)
        gaze.recordEyeOnly(.observedFail)
        model.tick(now: ProcessInfo.processInfo.systemUptime, geometry: gaze.geometry)
        XCTAssertEqual(model.flow?.state, .invalid(.interrupted))
        model.redo()
        XCTAssertNotEqual(model.flow?.state, .ready)
    }

    func testClosedAcceptedRegionIsClearedByStopOrRetry() throws {
        let model = try acceptedModel()
        model.end()
        model.interrupt()
        XCTAssertNil(model.reviewedRegion)
        XCTAssertNil(model.patchOffset)
    }

    func testClosedAcceptedRegionIsClearedByPhysicalLayoutChange() throws {
        let model = try acceptedModel()
        model.end()
        gaze.configure(size: CGSize(width: 301, height: 400), scale: 3, mode: .setupFront, generation: 1)
        model.tick(now: ProcessInfo.processInfo.systemUptime, geometry: gaze.geometry)
        XCTAssertNil(model.reviewedRegion)
        XCTAssertNil(model.patchOffset)
    }

    func testRevocationBlocksAcceptBeforeNextTimerOrCaptureEvent() throws {
        for revoke in approvalRevocations {
            let model = try candidateModel()
            revoke()
            model.accept()
            XCTAssertEqual(model.flow?.state, .invalid(.interrupted))
            XCTAssertNil(model.reviewedRegion)
            XCTAssertNil(model.flow?.candidate)
        }
    }

    func testRevocationBlocksRedoBeforeNextTimerOrCaptureEvent() throws {
        for revoke in approvalRevocations {
            let model = try startedModel()
            sendFrame(0)
            revoke()
            model.redo()
            XCTAssertEqual(model.flow?.state, .invalid(.interrupted))
            XCTAssertTrue(model.flow?.rawTrace.isEmpty == true)
        }
    }

    func testRevocationClearsTraceOnNextSourceCallback() throws {
        for revoke in approvalRevocations {
            let model = try startedModel()
            sendFrame(0)
            revoke()
            sendFrame(1)
            XCTAssertEqual(model.flow?.state, .invalid(.interrupted))
            XCTAssertTrue(model.flow?.rawTrace.isEmpty == true)
        }
    }

    func testClosedAcceptedFrontRegionClearsWhenApprovalIsRevoked() throws {
        let model = try acceptedModel()
        model.end()
        gaze.recordEyeOnly(.observedFail)
        model.tick(now: ProcessInfo.processInfo.systemUptime, geometry: gaze.geometry)
        XCTAssertNil(model.reviewedRegion)
        XCTAssertNil(model.patchOffset)
    }

    func testClosedAcceptedRegionClearsOnUnpreparedCaptureRestart() throws {
        for mode in [CaptureMode.setupFront, .liveRear] {
            let model = try acceptedModel()
            model.end()
            events.send(.reset(generation: 2, mode: mode))
            XCTAssertNil(model.reviewedRegion)
            XCTAssertNil(model.patchOffset)
        }
    }

    // Break caught: the capture generation in the setup ID blocked every deliberate same-display
    // front→rear handoff, so the accepted region could never reach rear composition.
    func testExplicitRearSelectionActivatesFrontRegionOnlyForThatRearSession() throws {
        let model = try acceptedModel()
        let front = try XCTUnwrap(model.reviewedRegion)
        model.end()
        model.prepareForRearSelection()
        gaze.configure(size: CGSize(width: 300, height: 400), scale: 3, mode: .liveRear, generation: 2)
        let rearGeometry = try XCTUnwrap(gaze.geometry)
        XCTAssertNil(model.rearRegion(for: rearGeometry), "Pending until the rear session actually starts")
        events.send(.reset(generation: 2, mode: .liveRear))
        model.tick(now: ProcessInfo.processInfo.systemUptime, geometry: gaze.geometry)
        XCTAssertEqual(model.reviewedRegion?.displayGeometry, front.displayGeometry, "Front provenance is kept")
        XCTAssertEqual(model.reviewedRegion?.provenance.captureGeneration, 1)
        XCTAssertEqual(model.patchOffset, ScreenPoint(x: 20, y: 0))
        XCTAssertNil(gaze.calibration, "The front fit is never reused in rear mode")
        let rear = try XCTUnwrap(model.rearRegion(for: rearGeometry))
        XCTAssertEqual(rear.displayGeometry, rearGeometry)
        XCTAssertEqual(rear.normalizedOffset, front.normalizedOffset)
        XCTAssertEqual(rear.normalizedRadii, front.normalizedRadii)
        XCTAssertNil(model.rearRegion(for: front.displayGeometry), "Only rear geometry can activate it")
        events.send(.reset(generation: 3, mode: .liveRear))
        XCTAssertNil(model.reviewedRegion)
        XCTAssertNil(model.rearRegion(for: rearGeometry))
        XCTAssertNil(model.patchOffset)
    }

    func testRetainedRearRegionClearsWhenPhysicalViewportMoves() throws {
        let model = try acceptedModel()
        model.end()
        model.prepareForRearSelection()
        gaze.configure(size: CGSize(width: 300, height: 400), scale: 3, mode: .liveRear, generation: 2)
        events.send(.reset(generation: 2, mode: .liveRear))
        gaze.configure(size: CGSize(width: 300, height: 400), scale: 3, mode: .liveRear, generation: 2,
                       origin: CGPoint(x: 0, y: 40))
        model.tick(now: ProcessInfo.processInfo.systemUptime, geometry: gaze.geometry)
        XCTAssertNil(model.reviewedRegion)
        XCTAssertNil(model.rearRegion(for: gaze.geometry))
    }

    func testRevokedFrontApprovalCannotBeRetainedByRearSelection() throws {
        let model = try acceptedModel()
        model.end()
        gaze.recordEyeOnly(.observedFail)
        model.prepareForRearSelection()
        events.send(.reset(generation: 2, mode: .liveRear))
        XCTAssertNil(model.reviewedRegion)
        XCTAssertNil(model.patchOffset)
    }

    func testClosedAcceptedRegionClearsOnPhysicalOriginOrScaleChange() throws {
        for (frame, scale) in [(CGRect(x: 10, y: 0, width: 300, height: 400), CGFloat(3)),
                               (CGRect(x: 0, y: 0, width: 300, height: 400), CGFloat(2))] {
            let model = try acceptedModel()
            model.end()
            model.layout(frame, scale: scale)
            XCTAssertNil(model.reviewedRegion)
            XCTAssertNil(model.patchOffset)
        }
    }

    private var approvalRevocations: [() -> Void] {
        [{ self.gaze.startCalibration() }, { self.gaze.startEvaluation() },
         { self.gaze.recordEyeOnly(.observedFail) }]
    }

    private func startedModel() throws -> AirTraceModel {
        gaze = try approvedGaze()
        let model = AirTraceModel()
        model.attach(events: events) { self.gaze }
        model.layout(CGRect(x: 0, y: 0, width: 300, height: 400), scale: 3)
        model.begin(gaze: gaze, generation: 1)
        return model
    }

    private func acceptedModel() throws -> AirTraceModel {
        let model = try candidateModel()
        model.accept()
        XCTAssertNotNil(model.reviewedRegion)
        model.nudgeOffset(dx: 20, dy: 0)
        return model
    }

    private func candidateModel() throws -> AirTraceModel {
        let model = try startedModel()
        for index in 0..<24 { sendFrame(index) }
        sendFrame(24, pinched: false)
        XCTAssertEqual(model.flow?.state, .candidateReady)
        return model
    }

    private func sendFrame(_ index: Int, hasHand: Bool = true, hasRawIdentity: Bool = true, pinched: Bool = true) {
        let time = ProcessInfo.processInfo.systemUptime
        let identity = FrameIdentity(generation: 1, captureTimestamp: 7000 + Double(index) * 0.02, receivedAt: time)
        let angle = 2 * Double.pi * Double(index % 24) / 24
        let point = CGPoint(x: (120 + 30 * cos(angle)) / 300, y: (140 + 20 * sin(angle)) / 400)
        let hand = HandObservation(identity: identity, indexTip: point,
                                   thumbTip: CGPoint(x: point.x + (pinched ? 1 : 60) / 300, y: point.y),
                                   indexConfidence: 0.9, thumbConfidence: 0.9)
        events.send(.eyes(hasRawIdentity ? eyes(x: 0.5, y: 0.5) : nil, identity: identity, mode: .setupFront))
        events.send(.hand(.success(hasHand ? hand : nil), identity: identity, mode: .setupFront))
    }

    private func approvedGaze() throws -> GazeSession {
        var session = GazeSession()
        session.configure(size: CGSize(width: 300, height: 400), scale: 3, mode: .setupFront, generation: 1)
        session.startCalibration()
        for target in 0..<9 {
            let start = 10 + Double(target) * 2
            let point = try XCTUnwrap(session.target).normalized
            session.targetPresented(at: start)
            for index in 0..<30 {
                let time = start + 0.51 + Double(index) * 0.03
                session.receive(try snapshot(x: point.x, y: point.y, time: time), now: time)
            }
            session.tick(now: start + 1.5)
        }
        session.startEvaluation()
        for window in 0..<10 {
            let start = 30 + Double(window) * 2
            let point = try XCTUnwrap(session.target).normalized
            session.targetPresented(at: start)
            for slot in 0..<20 {
                let time = start + 0.525 + Double(slot) * 0.05
                session.receive(try snapshot(x: point.x, y: point.y, time: time), now: time)
                session.tick(now: time)
            }
            session.tick(now: start + 1.5)
        }
        session.recordEyeOnly(.observedPass)
        XCTAssertTrue(session.report?.passesCompleteGate == true)
        return session
    }

    private func eyes(x: Double, y: Double) -> EyeObservation {
        EyeObservation(lookAtPoint: SIMD3(Float(x), Float(y), 1), leftEyeTranslation: SIMD3(-0.03, 0, 0),
                       rightEyeTranslation: SIMD3(0.03, 0, 0), leftBlink: 0, rightBlink: 0, isTracked: true)
    }

    private func snapshot(x: Double, y: Double, time: Double) throws -> CaptureSnapshot {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &image), kCVReturnSuccess)
        let identity = FrameIdentity(generation: 1, captureTimestamp: 5000 + time, receivedAt: time)
        let geometry = try XCTUnwrap(DisplayGeometry(viewport: CGSize(width: 300, height: 400), displayTransform: .identity, orientation: .right, mirrored: true))
        let packet = RenderPacket(identity: identity, image: try XCTUnwrap(image), geometry: geometry, mode: .setupFront)
        let observation = eyes(x: x, y: y)
        return CaptureSnapshot(sequence: 1, generation: 1, mode: .setupFront, status: .ready, support: nil,
                               renderPacket: packet, eyes: observation, eyeIdentity: identity, hand: nil,
                               handMessage: "fixture", rawEyes: observation, rawEyeIdentity: identity)
    }
}
