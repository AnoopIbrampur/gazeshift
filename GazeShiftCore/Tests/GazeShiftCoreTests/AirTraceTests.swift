import XCTest
@testable import GazeShiftCore

final class AirTraceTests: XCTestCase {
    // Break caught: an otherwise valid hand outline waits for eye data in the manual experiment.
    func testHandOnlyOutlineDoesNotNeedEyeSamples() throws {
        var session = try AirTraceSession(handOnlyGeometry: geometry(), captureGeneration: 1)
        for i in 0...24 {
            let angle = Double(i % 24) * 2 * .pi / 24
            let point = ScreenPoint(x: 110 + 30 * cos(angle), y: 130 + 20 * sin(angle))
            let time = 1 + Double(i) * 0.01
            session.observeSource(captureTimestamp: time, generation: 1, now: time, geometry: try geometry())
            session.consumeHand(hand(point: point, time: time, release: i == 24), now: time, geometry: try geometry())
        }
        XCTAssertEqual(session.state, .candidateReady)
    }
    // Break caught: recentering on gaze/centroid instead of the stationary fixation.
    func testClosedMinMaxEllipsePreservesAsymmetricFixationOffsetAndNeedsAcceptance() throws {
        var session = try makeSession()
        try closeStroke(&session)
        XCTAssertEqual(session.state, .candidateReady)
        XCTAssertNil(session.reviewedRegion)
        let candidate = try XCTUnwrap(session.candidate)
        XCTAssertEqual(candidate.normalizedOffset.x, -40.0 / 300, accuracy: 0.000001)
        XCTAssertEqual(candidate.normalizedOffset.y, -70.0 / 400, accuracy: 0.000001)
        XCTAssertEqual(candidate.normalizedRadii, ScreenPoint(x: 0.1, y: 0.05))
        XCTAssertEqual(session.rawTrace.count, 25)
        let region = try session.acceptCandidate()
        XCTAssertEqual(session.state, .accepted)
        let ellipse = try region.displayEllipse(gaze: ScreenPoint(x: 160, y: 210), geometry: geometry())
        XCTAssertEqual(ellipse.center.x, 120, accuracy: 0.000001)
        XCTAssertEqual(ellipse.center.y, 140, accuracy: 0.000001)
        XCTAssertEqual(ellipse.radii, ScreenPoint(x: 30, y: 20))
    }

    // Break caught: joining a new valid segment to history after a missing pair.
    func testInvalidPairClearsWholeStrokeAndRequiresExplicitRedo() throws {
        var session = try makeSession()
        consume(&session, point: ScreenPoint(x: 140, y: 130), time: 1)
        session.consume(hand: nil, gaze: nil, now: 1.01, geometry: try geometry())
        XCTAssertEqual(session.state, .invalid(.missingPair))
        XCTAssertTrue(session.rawTrace.isEmpty)
        XCTAssertNil(session.candidate)
        consume(&session, point: ScreenPoint(x: 100, y: 130), time: 1.02)
        XCTAssertEqual(session.state, .invalid(.missingPair))
        session.redo()
        XCTAssertEqual(session.state, .ready)
        try closeStroke(&session, start: 2)
        XCTAssertEqual(session.state, .candidateReady)
    }

    // Break caught: counting repeated points or accepting fewer than 20 distinct points.
    func testMinimumRequiresTwentyDistinctPointsAndClosedNonzeroBounds() throws {
        var insufficient = try makeSession()
        try closeStroke(&insufficient, count: 19)
        XCTAssertEqual(insufficient.state, .invalid(.insufficientSamples))
        var sufficient = try makeSession()
        try closeStroke(&sufficient, count: 20)
        XCTAssertEqual(sufficient.state, .candidateReady)
        var stationary = try makeSession()
        for i in 0..<24 { consume(&stationary, point: ScreenPoint(x: 100, y: 130), time: 1 + Double(i) * 0.01) }
        consume(&stationary, point: ScreenPoint(x: 100, y: 130), time: 1.24, release: true)
        XCTAssertEqual(stationary.state, .invalid(.insufficientSamples))
        var flat = try makeSession()
        for i in 0..<20 { consume(&flat, point: ScreenPoint(x: 90 + Double(i), y: 130), time: 1 + Double(i) * 0.01) }
        consume(&flat, point: ScreenPoint(x: 90, y: 130), time: 1.2, release: true)
        XCTAssertEqual(flat.state, .invalid(.degenerateStroke))
        var open = try makeSession()
        for i in 0..<20 { consume(&open, point: ScreenPoint(x: 90 + Double(i), y: 120 + Double(i)), time: 1 + Double(i) * 0.01) }
        consume(&open, point: ScreenPoint(x: 130, y: 150), time: 1.2, release: true)
        XCTAssertEqual(open.state, .invalid(.openStroke))
    }

    // Break caught: unrelated current gaze, old generations, stale samples or gaps entering a trace.
    func testRejectsStaleUnpairedGenerationAndInterruptedCapture() throws {
        for reason in [AirTraceRejection.unpairedCapture, .generationChanged, .stalePair, .captureGap, .interrupted] {
            var session = try makeSession()
            consume(&session, point: ScreenPoint(x: 140, y: 130), time: 1)
            let hand = hand(point: ScreenPoint(x: 135, y: 130), time: 1.01, generation: reason == .generationChanged ? 2 : 1)
            let gaze = AirTraceGazeSample(point: fixation, qualityValid: true, captureTimestamp: reason == .unpairedCapture ? 1.02 : 1.01, generation: reason == .generationChanged ? 2 : 1)
            if reason == .interrupted { session.interrupt() }
            else if reason == .captureGap {
                consume(&session, point: ScreenPoint(x: 135, y: 130), time: 1.3)
            } else {
                session.consume(hand: hand, gaze: gaze, now: reason == .stalePair ? 2 : 1.02, geometry: try geometry())
            }
            XCTAssertEqual(session.state, .invalid(reason))
            XCTAssertTrue(session.rawTrace.isEmpty)
        }
    }

    // Break caught: gross fixation drift, occlusion, NaN or missing hand confidence surviving.
    func testRejectsDriftLowQualityNonfiniteAndOffscreenPoints() throws {
        let cases: [(AirTraceHandSample, AirTraceGazeSample, AirTraceRejection)] = [
            (hand(point: ScreenPoint(x: 140, y: 130), time: 1.01), AirTraceGazeSample(point: ScreenPoint(x: 201, y: 200), qualityValid: true, captureTimestamp: 1.01, generation: 1), .fixationDrift),
            (hand(point: ScreenPoint(x: 140, y: 130), time: 1.01), AirTraceGazeSample(point: fixation, qualityValid: false, captureTimestamp: 1.01, generation: 1), .invalidGaze),
            (hand(point: ScreenPoint(x: .nan, y: 130), time: 1.01), AirTraceGazeSample(point: fixation, qualityValid: true, captureTimestamp: 1.01, generation: 1), .invalidHand),
            (hand(point: ScreenPoint(x: 301, y: 130), time: 1.01), AirTraceGazeSample(point: fixation, qualityValid: true, captureTimestamp: 1.01, generation: 1), .invalidHand),
            (AirTraceHandSample(indexTip: ScreenPoint(x: 140, y: 130), thumbTip: ScreenPoint(x: 141, y: 130), indexConfidence: 0.1, thumbConfidence: 1, captureTimestamp: 1.01, generation: 1), AirTraceGazeSample(point: fixation, qualityValid: true, captureTimestamp: 1.01, generation: 1), .invalidHand)
        ]
        for (hand, gaze, reason) in cases {
            var session = try makeSession()
            consume(&session, point: ScreenPoint(x: 140, y: 130), time: 1)
            session.consume(hand: hand, gaze: gaze, now: 1.01, geometry: try geometry())
            XCTAssertEqual(session.state, .invalid(reason))
            XCTAssertTrue(session.rawTrace.isEmpty)
        }
    }

    // Break caught: silently retaining a region across physical setup/geometry changes.
    func testGeometryChangeInvalidatesAndOnlyExplicitModeTransitionRetainsRegion() throws {
        var session = try makeSession()
        try closeStroke(&session)
        let region = try session.acceptCandidate()
        let rear = try geometry(mode: .rearLive)
        XCTAssertThrowsError(try region.displayEllipse(gaze: fixation, geometry: rear))
        let transitioned = try region.retainedForModeTransition(to: rear)
        XCTAssertNoThrow(try transitioned.displayEllipse(gaze: fixation, geometry: rear))
        let changed = try geometry(mode: .rearLive, setup: "different-distance")
        XCTAssertThrowsError(try region.retainedForModeTransition(to: changed))
        XCTAssertThrowsError(try transitioned.displayEllipse(gaze: fixation, geometry: changed))
        session.consume(hand: nil, gaze: nil, now: 2, geometry: rear)
        XCTAssertEqual(session.state, .invalid(.geometryChanged))
        XCTAssertNil(session.reviewedRegion)
        XCTAssertThrowsError(try makeSession(fixation: ScreenPoint(x: .infinity, y: 200)))
    }

    // Break caught: pinch chatter ending a stroke before the release threshold is crossed.
    func testPinchHysteresisAndRepeatedCaptureCannotFinishOrGrowStroke() throws {
        var session = try makeSession()
        consume(&session, point: ScreenPoint(x: 140, y: 130), time: 1)
        let uncertain = AirTraceHandSample(indexTip: ScreenPoint(x: 135, y: 130), thumbTip: ScreenPoint(x: 155, y: 130), indexConfidence: 1, thumbConfidence: 1, captureTimestamp: 1.01, generation: 1)
        session.consume(hand: uncertain, gaze: AirTraceGazeSample(point: fixation, qualityValid: true, captureTimestamp: 1.01, generation: 1), now: 1.01, geometry: try geometry())
        XCTAssertEqual(session.state, .tracing)
        XCTAssertEqual(session.rawTrace.count, 2)
        consume(&session, point: ScreenPoint(x: 130, y: 130), time: 1.01)
        XCTAssertEqual(session.state, .invalid(.duplicateCapture))
        XCTAssertTrue(session.rawTrace.isEmpty)
    }

    // Break caught: a mutually paired callback from an earlier session starting a fresh stroke.
    func testOldGenerationCannotStartAStrokeAfterSessionInitializationOrRedo() throws {
        var session = try makeSession()
        let oldHand = hand(point: ScreenPoint(x: 140, y: 130), time: 1, generation: 0)
        let oldGaze = AirTraceGazeSample(point: fixation, qualityValid: true, captureTimestamp: 1, generation: 0)
        session.consume(hand: oldHand, gaze: oldGaze, now: 1, geometry: try geometry())
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(session.rawTrace.isEmpty)
        consume(&session, point: ScreenPoint(x: 140, y: 130), time: 1.01)
        session.redo()
        session.consume(hand: oldHand, gaze: oldGaze, now: 1, geometry: try geometry())
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(session.rawTrace.isEmpty)
    }

    // Break caught: nonfinite/future timestamps or mixed-generation pairs surviving an active stroke.
    func testMalformedTimestampsAndMixedGenerationPairClearStroke() throws {
        let cases: [(Double, Double, Double, UInt64, AirTraceRejection)] = [
            (.nan, .nan, 1.02, 1, .invalidTimestamp),
            (1.01, 1.01, .infinity, 1, .invalidTimestamp),
            (1.01, 1.01, 1.0, 1, .invalidTimestamp),
            (-0.1, -0.1, 1.02, 1, .invalidTimestamp),
            (1.01, 1.01, 1.02, 2, .unpairedCapture)
        ]
        for (handTime, gazeTime, now, gazeGeneration, reason) in cases {
            var session = try makeSession()
            consume(&session, point: ScreenPoint(x: 140, y: 130), time: 1)
            session.consume(
                hand: hand(point: ScreenPoint(x: 135, y: 130), time: handTime),
                gaze: AirTraceGazeSample(point: fixation, qualityValid: true,
                                        captureTimestamp: gazeTime, generation: gazeGeneration),
                now: now, geometry: try geometry())
            XCTAssertEqual(session.state, .invalid(reason))
            XCTAssertTrue(session.rawTrace.isEmpty)
            XCTAssertNil(session.candidate)
        }
    }

    // Break caught: accepting a confident index tip when the thumb is invalid or offscreen.
    func testBothHandLandmarksAndGazePointAreRequiredThroughoutStroke() throws {
        let invalidThumbs: [(Double, ScreenPoint)] = [
            (0.1, ScreenPoint(x: 136, y: 130)), (.nan, ScreenPoint(x: 136, y: 130)),
            (.infinity, ScreenPoint(x: 136, y: 130)), (1.1, ScreenPoint(x: 136, y: 130)),
            (1, ScreenPoint(x: .nan, y: 130)), (1, ScreenPoint(x: 301, y: 130))
        ]
        for (thumbConfidence, thumbPoint) in invalidThumbs {
            var session = try makeSession()
            consume(&session, point: ScreenPoint(x: 140, y: 130), time: 1)
            let invalidHand = AirTraceHandSample(
                indexTip: ScreenPoint(x: 135, y: 130), thumbTip: thumbPoint,
                indexConfidence: 1, thumbConfidence: thumbConfidence,
                captureTimestamp: 1.01, generation: 1)
            session.consume(hand: invalidHand, gaze: AirTraceGazeSample(
                point: fixation, qualityValid: true, captureTimestamp: 1.01, generation: 1),
                now: 1.01, geometry: try geometry())
            XCTAssertEqual(session.state, .invalid(.invalidHand))
            XCTAssertTrue(session.rawTrace.isEmpty)
        }
        var missingGazePoint = try makeSession()
        consume(&missingGazePoint, point: ScreenPoint(x: 140, y: 130), time: 1)
        missingGazePoint.consume(hand: hand(point: ScreenPoint(x: 135, y: 130), time: 1.01),
            gaze: AirTraceGazeSample(point: nil, qualityValid: true, captureTimestamp: 1.01, generation: 1),
            now: 1.01, geometry: try geometry())
        XCTAssertEqual(missingGazePoint.state, .invalid(.invalidGaze))
        XCTAssertTrue(missingGazePoint.rawTrace.isEmpty)
    }

    // Break caught: intermediate addition/multiplication overflowing despite finite valid bounds.
    func testFiniteBoundsDoNotOverflowNormalizedEllipseMath() throws {
        let largeGeometry = try RenderGeometry(width: 1.6e308, height: 1e307, scale: 0.1,
            orientation: .portrait, mode: .frontSetup, viewingSetupID: "numeric-boundary")
        let fixedPoint = ScreenPoint(x: 5e307, y: 5e306)
        var session = try AirTraceSession(geometry: largeGeometry, fixation: fixedPoint,
            eyeStateDescription: "binocular-open", captureGeneration: 1)
        for i in 0...24 {
            let angle = Double(i % 24) * 2 * .pi / 24
            let point = ScreenPoint(x: 1.2e308 + 1e307 * cos(angle), y: 5e306 + 2e306 * sin(angle))
            let time = 1 + Double(i) * 0.01
            session.consume(hand: AirTraceHandSample(indexTip: point,
                thumbTip: ScreenPoint(x: point.x + (i == 24 ? 1e307 : 1e305), y: point.y),
                indexConfidence: 1, thumbConfidence: 1, captureTimestamp: time, generation: 1),
                gaze: AirTraceGazeSample(point: fixedPoint, qualityValid: true,
                                        captureTimestamp: time, generation: 1),
                now: time, geometry: largeGeometry)
        }
        let candidate = try XCTUnwrap(session.candidate)
        XCTAssertEqual(candidate.normalizedOffset.x, 0.4375, accuracy: 0.000001)
        XCTAssertEqual(candidate.normalizedOffset.y, 0, accuracy: 0.000001)
        XCTAssertEqual(candidate.normalizedRadii.x, 0.0625, accuracy: 0.000001)
        XCTAssertEqual(candidate.normalizedRadii.y, 0.2, accuracy: 0.000001)
    }

    private let fixation = ScreenPoint(x: 150, y: 200)
    private func geometry(mode: TrackingMode = .frontSetup, setup: String = "seated-40cm") throws -> RenderGeometry {
        try RenderGeometry(width: 300, height: 400, scale: 2, orientation: .portrait, mode: mode, viewingSetupID: setup)
    }
    private func makeSession(fixation: ScreenPoint? = nil) throws -> AirTraceSession {
        try AirTraceSession(geometry: geometry(), fixation: fixation ?? self.fixation, eyeStateDescription: "binocular-open", captureGeneration: 1)
    }
    private func hand(point: ScreenPoint, time: Double, generation: UInt64 = 1, release: Bool = false) -> AirTraceHandSample {
        AirTraceHandSample(indexTip: point, thumbTip: ScreenPoint(x: point.x + (release ? 40 : 1), y: point.y), indexConfidence: 1, thumbConfidence: 1, captureTimestamp: time, generation: generation)
    }
    private func consume(_ session: inout AirTraceSession, point: ScreenPoint, time: Double, release: Bool = false) {
        session.consume(hand: hand(point: point, time: time, release: release), gaze: AirTraceGazeSample(point: fixation, qualityValid: true, captureTimestamp: time, generation: 1), now: time, geometry: try! geometry())
    }
    private func closeStroke(_ session: inout AirTraceSession, count: Int = 24, start: Double = 1) throws {
        for i in 0..<count {
            let angle = Double(i) * 2 * .pi / Double(count)
            consume(&session, point: ScreenPoint(x: 110 + 30 * cos(angle), y: 130 + 20 * sin(angle)), time: start + Double(i) * 0.01)
        }
        consume(&session, point: ScreenPoint(x: 140, y: 130), time: start + Double(count) * 0.01, release: true)
    }
}
