import XCTest
@testable import GazeShiftCore

final class ScreenTouchTraceTests: XCTestCase {
    private func geometry(mode: TrackingMode = .rearLive, width: Double = 400) throws -> RenderGeometry {
        try RenderGeometry(width: width, height: 300, scale: 3, orientation: .landscapeLeft,
                           mode: mode, viewingSetupID: "screen-touch")
    }
    private func session() throws -> AirTraceSession {
        try AirTraceSession(screenTouchGeometry: geometry(), captureGeneration: 1)
    }
    private func point(_ i: Int) -> ScreenPoint {
        let angle = Double(i % 24) * 2 * .pi / 24
        return ScreenPoint(x: 120 + 30 * cos(angle), y: 140 + 20 * sin(angle))
    }
    private func source(_ session: inout AirTraceSession, at time: Double, generation: UInt64 = 1) throws {
        session.observeSource(captureTimestamp: time, generation: generation, now: time, geometry: try geometry())
    }
    private func trace(_ session: inout AirTraceSession) throws {
        session.startDrawing(at: 1, geometry: try geometry())
        for i in 0...24 {
            let time = 1.01 + Double(i) * 0.01
            try source(&session, at: time)
            session.consumeTouch(point(i), now: time, geometry: try geometry())
        }
    }

    // A rear touch attempt must stay honest about mode and must not record before Start or without a live source.
    func testRearTouchRequiresExplicitStartAndRealCameraSource() throws {
        XCTAssertThrowsError(try AirTraceSession(screenTouchGeometry: geometry(mode: .frontSetup), captureGeneration: 1))
        var session = try session()
        session.consumeTouch(point(0), now: 0.9, geometry: try geometry())
        XCTAssertEqual(session.state, .ready)
        session.startDrawing(at: 1, geometry: try geometry())
        session.consumeTouch(point(0), now: 1.01, geometry: try geometry())
        XCTAssertEqual(session.state, .armed)
        XCTAssertTrue(session.rawTrace.isEmpty)
        session.observeSource(captureTimestamp: 0.99, generation: 1, now: 1.01, geometry: try geometry())
        session.consumeTouch(point(0), now: 1.01, geometry: try geometry())
        XCTAssertTrue(session.rawTrace.isEmpty)
        try source(&session, at: 1.02)
        session.consumeTouch(point(0), now: 1.02, geometry: try geometry())
        XCTAssertEqual(session.rawTrace, [ScreenPoint(x: 150, y: 140)])
        XCTAssertEqual(session.state, .tracing)
        XCTAssertTrue(session.eyeStateDescription.contains("Eye tracking disabled"))
    }

    // Touch finish uses the existing ellipse/review gates; no camera-derived hand or eye point is synthesized.
    func testTouchEllipseFreezesForSeparateAcceptance() throws {
        var session = try session()
        try trace(&session)
        session.finishDrawing(now: 1.26, geometry: try geometry())
        XCTAssertEqual(session.state, .candidateReady)
        XCTAssertNil(session.reviewedRegion)
        let saved = session.rawTrace
        session.consumeTouch(ScreenPoint(x: 10, y: 10), now: 2, geometry: try geometry())
        XCTAssertEqual(session.rawTrace, saved)
        let reviewed = try session.acceptCandidate()
        let ellipse = try reviewed.screenFixedEllipse(geometry: geometry())
        XCTAssertEqual(ellipse.center.x, 120, accuracy: 1e-9)
        XCTAssertEqual(ellipse.center.y, 140, accuracy: 1e-9)
        XCTAssertEqual(ellipse.radii.x, 30, accuracy: 1e-9)
        XCTAssertEqual(ellipse.radii.y, 20, accuracy: 1e-9)
        XCTAssertEqual(reviewed.provenance.captureGeneration, 1)
    }

    // A stationary finger may pause while the real rear camera keeps streaming; camera loss still clears the attempt.
    func testOnlyCameraFreshnessExpiresStationaryTouch() throws {
        var session = try session()
        session.startDrawing(at: 1, geometry: try geometry())
        try source(&session, at: 1.01)
        session.consumeTouch(point(0), now: 1.01, geometry: try geometry())
        for i in 1...10 { try source(&session, at: 1.01 + Double(i) * 0.1) }
        session.expireInputs(now: 2.05, geometry: try geometry())
        XCTAssertEqual(session.state, .tracing)
        XCTAssertEqual(session.rawTrace.count, 1)
        session.consumeTouch(point(1), now: 2.06, geometry: try geometry())
        XCTAssertEqual(session.rawTrace.count, 2)
        session.expireInputs(now: 2.4, geometry: try geometry())
        XCTAssertEqual(session.state, .invalid(.stalePair))
        XCTAssertTrue(session.rawTrace.isEmpty)
    }

    // Invalid UI coordinates, backwards/nonfinite clocks, source generation and geometry cannot survive as an active outline.
    func testInvalidTouchClockGenerationAndGeometryClearStroke() throws {
        for variant in 0..<6 {
            var session = try session()
            session.startDrawing(at: 1, geometry: try geometry())
            try source(&session, at: 1.01)
            session.consumeTouch(point(0), now: 1.01, geometry: try geometry())
            switch variant {
            case 0: session.consumeTouch(ScreenPoint(x: .nan, y: 10), now: 1.02, geometry: try geometry())
            case 1: session.consumeTouch(ScreenPoint(x: 401, y: 10), now: 1.02, geometry: try geometry())
            case 2: session.consumeTouch(point(1), now: .nan, geometry: try geometry())
            case 3: session.consumeTouch(point(1), now: 1.0, geometry: try geometry())
            case 4: try source(&session, at: 1.02, generation: 2)
            default: session.consumeTouch(point(1), now: 1.02, geometry: try geometry(width: 401))
            }
            let reason: AirTraceRejection = [.invalidTouch, .invalidTouch, .invalidTimestamp, .invalidTimestamp, .generationChanged, .geometryChanged][variant]
            XCTAssertEqual(session.state, .invalid(reason))
            XCTAssertTrue(session.rawTrace.isEmpty)
            XCTAssertNil(session.candidate)
        }
    }

    // Existing front hand/gaze/index callbacks must never append in the touch mode.
    func testHandAndGazeCannotDrawInTouchMode() throws {
        var session = try session()
        session.startDrawing(at: 1, geometry: try geometry())
        try source(&session, at: 1.01)
        session.consumeIndex(AirTraceIndexSample(indexTip: point(0), indexConfidence: 1,
            captureTimestamp: 1.01, generation: 1), captureTimestamp: 1.01, now: 1.01, geometry: try geometry())
        session.consumeHand(AirTraceHandSample(indexTip: point(0), thumbTip: point(0), indexConfidence: 1,
            thumbConfidence: 1, captureTimestamp: 1.01, generation: 1), now: 1.01, geometry: try geometry())
        XCTAssertFalse(session.observeGaze(AirTraceGazeSample(point: point(0), qualityValid: true,
            captureTimestamp: 1.01, generation: 1), now: 1.01, geometry: try geometry()))
        XCTAssertEqual(session.state, .armed)
        XCTAssertTrue(session.rawTrace.isEmpty)
    }

    // A diagonal out-and-back stroke has a bounding box but encloses no area and cannot manufacture an ellipse.
    func testFinishRejectsEmptyShortOpenAndClosedCollinearTouch() throws {
        for variant in 0..<4 {
            var session = try session()
            session.startDrawing(at: 1, geometry: try geometry())
            let count = variant == 0 ? 0 : (variant == 1 ? 19 : 25)
            for i in 0..<count {
                let time = 1.01 + Double(i) * 0.01
                let position = variant == 2 ? ScreenPoint(x: 50 + Double(i), y: 50 + Double(i))
                    : (variant == 3 ? ScreenPoint(x: 50 + Double(i % 24), y: 50 + Double(i % 24)) : point(i))
                try source(&session, at: time)
                session.consumeTouch(position, now: time, geometry: try geometry())
            }
            session.finishDrawing(now: 1.26, geometry: try geometry())
            let reason: AirTraceRejection = [.insufficientSamples, .insufficientSamples, .openStroke, .degenerateStroke][variant]
            XCTAssertEqual(session.state, .invalid(reason))
            XCTAssertThrowsError(try session.acceptCandidate())
        }
    }
}
