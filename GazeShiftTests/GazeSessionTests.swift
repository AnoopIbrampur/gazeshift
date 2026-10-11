import XCTest
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
