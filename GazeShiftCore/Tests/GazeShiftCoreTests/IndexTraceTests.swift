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

    // Measure-style tolerance: one missed, blurred, low-confidence, off-view or stale frame is skipped.
    func testBriefIndexDropoutsAreSkippedNotFatal() throws {
        for variant in 0..<5 {
            var session = try session()
            session.startDrawing(at: 1, geometry: try geometry())
            try consume(&session, sample(0))
            let bad: AirTraceIndexSample? = switch variant {
            case 0: nil
            case 1: sample(1, time: 1.02, confidence: 0.1)
            case 2: AirTraceIndexSample(indexTip: ScreenPoint(x: 301, y: 1), indexConfidence: 1, captureTimestamp: 1.02, generation: 1)
            case 3: AirTraceIndexSample(indexTip: ScreenPoint(x: .nan, y: 1), indexConfidence: 1, captureTimestamp: 1.02, generation: 1)
            default: sample(1, time: 1.01) // duplicate capture
            }
            session.consumeIndex(bad, captureTimestamp: bad?.captureTimestamp ?? 1.02, now: 1.02, geometry: try geometry())
            XCTAssertEqual(session.state, .tracing, "variant \(variant)")
            XCTAssertEqual(session.rawTrace.count, 1)
            try consume(&session, sample(2, time: 1.03))
            XCTAssertEqual(session.rawTrace.count, 2, "drawing resumes after the dropout")
        }
    }

    // Losing the finger for longer than the gap, a restart or a camera stall still clears the stroke.
    func testLongLossRestartOrStalledSourceStillClearsStroke() throws {
        var gap = try session()
        gap.startDrawing(at: 1, geometry: try geometry())
        try consume(&gap, sample(0))
        // Camera frames keep arriving but Vision never sees the finger again.
        var t = 1.06
        while t < 1.01 + AirTraceDefaults.indexMaximumHandGapSeconds + 0.1 {
            gap.observeSource(captureTimestamp: t, generation: 1, now: t, geometry: try geometry())
            gap.consumeIndex(nil, captureTimestamp: t, now: t, geometry: try geometry())
            if t < 1.01 + AirTraceDefaults.indexMaximumHandGapSeconds - 0.05 { XCTAssertEqual(gap.state, .tracing) }
            t += 0.05
        }
        if case .invalid = gap.state {} else { XCTFail("long loss must clear, got \(gap.state)") }
        XCTAssertTrue(gap.rawTrace.isEmpty)

        var restart = try session()
        restart.startDrawing(at: 1, geometry: try geometry())
        try consume(&restart, sample(0))
        let other = sample(1, time: 1.02, generation: 2)
        restart.consumeIndex(other, captureTimestamp: 1.02, now: 1.02, geometry: try geometry())
        XCTAssertEqual(restart.state, .invalid(.generationChanged))

        var watchdog = try session()
        watchdog.startDrawing(at: 1, geometry: try geometry())
        try consume(&watchdog, sample(0))
        watchdog.expireInputs(now: 1.01 + AirTraceDefaults.indexMaximumHandGapSeconds + 0.05, geometry: try geometry())
        XCTAssertEqual(watchdog.state, .invalid(.stalePair))
    }

    // Jitter is smoothed and a loosely closed loop is auto-closed on Finish.
    func testSmoothingAndLooseClosure() throws {
        var smooth = try self.session()
        smooth.startDrawing(at: 1, geometry: try geometry())
        try consume(&smooth, AirTraceIndexSample(indexTip: ScreenPoint(x: 100, y: 100), indexConfidence: 1, captureTimestamp: 1.01, generation: 1))
        try consume(&smooth, AirTraceIndexSample(indexTip: ScreenPoint(x: 120, y: 100), indexConfidence: 1, captureTimestamp: 1.02, generation: 1))
        XCTAssertEqual(smooth.rawTrace.last?.x ?? 0, 110, accuracy: 1e-9)

        var loose = try self.session()
        loose.startDrawing(at: 1, geometry: try geometry())
        // Three-quarter circle: ends ~85 pt from the start (> old 15 pt limit, < 0.25 diagonal).
        for i in 0..<18 { try consume(&loose, AirTraceIndexSample(indexTip: ScreenPoint(x: 150 + 60 * cos(Double(i) * .pi / 12), y: 200 + 60 * sin(Double(i) * .pi / 12)), indexConfidence: 1, captureTimestamp: 1.01 + Double(i) * 0.01, generation: 1)) }
        loose.finishDrawing(now: 1.19, geometry: try geometry())
        XCTAssertEqual(loose.state, .candidateReady)
    }

    // Explicit Finish cannot bypass minimum samples, closure, area or current capture freshness.
    func testFinishRejectsEmptyShortOpenFlatAndStaleOutlines() throws {
        for variant in 0..<5 {
            var session = try session()
            session.startDrawing(at: 1, geometry: try geometry())
            let count = variant == 0 ? 0 : (variant == 1 ? AirTraceDefaults.indexMinimumDistinctSamples - 1 : 25)
            for i in 0..<count {
                let point = variant == 2 ? ScreenPoint(x: 20 + 10 * Double(i), y: 20 + 10 * Double(i))
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
