import XCTest
@testable import GazeShiftCore

final class IndexTraceTests: XCTestCase {
    private func geometry() throws -> RenderGeometry {
        try RenderGeometry(width: 300, height: 400, scale: 3, orientation: .portrait,
                           mode: .frontSetup, viewingSetupID: "index-only")
    }
    private func session() throws -> AirTraceSession {
        try AirTraceSession(indexOnlyGeometry: geometry(), captureGeneration: 1)
    }
    private func sample(_ i: Int, time: Double? = nil, confidence: Double = 1, generation: UInt64 = 1) -> AirTraceIndexSample {
        let angle = Double(i % 24) * 2 * .pi / 24
        return AirTraceIndexSample(indexTip: ScreenPoint(x: 120 + 30 * cos(angle), y: 140 + 20 * sin(angle)),
            indexConfidence: confidence, captureTimestamp: time ?? 1.01 + Double(i) * 0.01, generation: generation)
    }
    private func consume(_ session: inout AirTraceSession, _ sample: AirTraceIndexSample, now: Double? = nil) throws {
        let now = now ?? sample.captureTimestamp
        session.observeSource(captureTimestamp: sample.captureTimestamp, generation: sample.generation,
                              now: now, geometry: try geometry())
        session.consumeIndex(sample, captureTimestamp: sample.captureTimestamp, now: now, geometry: try geometry())
    }

    // Removing the explicit arm gate or replaying an in-flight pre-Start callback must fail here.
    func testOrdinaryMovementAndPreStartCallbacksNeverBecomeDrawingPoints() throws {
        var session = try session()
        for i in 0..<24 { try consume(&session, sample(i, time: 0.5 + Double(i) * 0.01)) }
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(session.rawTrace.isEmpty)
        XCTAssertNil(session.candidate)
        session.startDrawing(at: 1, geometry: try geometry())
        session.consumeIndex(sample(0, time: 0.99), captureTimestamp: 0.99, now: 1.01, geometry: try geometry())
        XCTAssertEqual(session.state, .armed)
        XCTAssertTrue(session.rawTrace.isEmpty)
        // The armed wait has no invented last hand timestamp; a delayed first sample can still start.
        session.expireInputs(now: 1.5, geometry: try geometry())
        try consume(&session, sample(0, time: 1.51))
        XCTAssertEqual(session.state, .tracing)
        XCTAssertEqual(session.rawTrace.count, 1)
    }

    // Finish freezes actual points, and only Accept commits a region; no thumb or gaze exists here.
    func testIndexOnlyFinishFreezesCandidateAndAcceptIsSeparate() throws {
        var session = try session()
        session.startDrawing(at: 1, geometry: try geometry())
        for i in 0...24 { try consume(&session, sample(i)) }
        session.startDrawing(at: 1.25, geometry: try geometry()) // Repeated Start cannot erase a stroke.
        XCTAssertEqual(session.rawTrace.count, 25)
        session.finishDrawing(now: 1.26, geometry: try geometry())
        XCTAssertEqual(session.state, .candidateReady)
        XCTAssertNil(session.reviewedRegion)
        let points = session.rawTrace
        session.consumeIndex(nil, captureTimestamp: 1.27, now: 1.27, geometry: try geometry())
        session.observeSource(captureTimestamp: 1.28, generation: 1, now: 1.28, geometry: try geometry())
        session.expireInputs(now: 2, geometry: try geometry())
        session.finishDrawing(now: 2, geometry: try geometry())
        XCTAssertEqual(session.state, .candidateReady)
        XCTAssertEqual(session.rawTrace, points)
        XCTAssertNotNil(try session.acceptCandidate())
    }

    // Index-only mode retains the original confidence, age, generation, bounds and source checks.
    func testInvalidIndexOrSourceClearsActiveStroke() throws {
        for reason in [AirTraceRejection.missingPair, .invalidHand, .stalePair, .generationChanged, .duplicateCapture] {
            var session = try session()
            session.startDrawing(at: 1, geometry: try geometry())
            try consume(&session, sample(0))
            let next = sample(1, time: reason == .duplicateCapture ? 1.01 : 1.02,
                              confidence: reason == .invalidHand ? 0.1 : 1,
                              generation: reason == .generationChanged ? 2 : 1)
            session.consumeIndex(reason == .missingPair ? nil : next, captureTimestamp: next.captureTimestamp,
                                 now: reason == .stalePair ? 2 : 1.02, geometry: try geometry())
            XCTAssertEqual(session.state, .invalid(reason))
            XCTAssertTrue(session.rawTrace.isEmpty)
        }
        for point in [ScreenPoint(x: .nan, y: 1), ScreenPoint(x: 301, y: 1)] {
            var session = try session()
            session.startDrawing(at: 1, geometry: try geometry())
            try consume(&session, sample(0))
            session.consumeIndex(AirTraceIndexSample(indexTip: point, indexConfidence: 1,
                captureTimestamp: 1.02, generation: 1), captureTimestamp: 1.02, now: 1.02, geometry: try geometry())
            XCTAssertEqual(session.state, .invalid(.invalidHand))
        }
    }

    // Explicit Finish cannot bypass minimum samples, closure, area or current capture freshness.
    func testFinishRejectsEmptyShortOpenFlatAndStaleOutlines() throws {
        for variant in 0..<5 {
            var session = try session()
            session.startDrawing(at: 1, geometry: try geometry())
            let count = variant == 0 ? 0 : (variant == 1 ? 19 : 25)
            for i in 0..<count {
                let point = variant == 2 ? ScreenPoint(x: 50 + Double(i), y: 50 + Double(i))
                    : (variant == 3 ? ScreenPoint(x: 50 + Double(i % 24), y: 50) : sample(i).indexTip)
                try consume(&session, AirTraceIndexSample(indexTip: point, indexConfidence: 1,
                    captureTimestamp: 1.01 + Double(i) * 0.01, generation: 1))
            }
            session.finishDrawing(now: variant == 4 ? 2 : 1.26, geometry: try geometry())
            let reason: AirTraceRejection = [.insufficientSamples, .insufficientSamples, .openStroke, .degenerateStroke, .stalePair][variant]
            XCTAssertEqual(session.state, .invalid(reason))
            XCTAssertThrowsError(try session.acceptCandidate())
        }
    }
}
