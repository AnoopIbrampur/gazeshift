import XCTest
import GazeShiftCore
@testable import GazeShiftFlow

final class IndexTraceFlowTests: XCTestCase {
    private func geometry() throws -> RenderGeometry {
        try RenderGeometry(width: 300, height: 400, scale: 3, orientation: .portrait,
                           mode: .frontSetup, viewingSetupID: "index-flow")
    }
    private func flow() throws -> AirTraceFlow {
        AirTraceFlow(session: try AirTraceSession(indexOnlyGeometry: geometry(), captureGeneration: 1))
    }
    private func input(_ i: Int, time: Double? = nil) -> NormalizedIndexInput {
        let angle = Double(i % 24) * 2 * .pi / 24
        return NormalizedIndexInput(frame: CaptureFrameKey(generation: 1, frameTimestamp: Double(i)),
            captureTime: time ?? 1.01 + Double(i) * 0.01,
            indexTip: ScreenPoint(x: (120 + 30 * cos(angle)) / 300, y: (140 + 20 * sin(angle)) / 400),
            indexConfidence: 1)
    }
    private func deliver(_ flow: inout AirTraceFlow, _ input: NormalizedIndexInput) throws {
        flow.recordSource(frame: input.frame, captureTime: input.captureTime, now: input.captureTime, geometry: try geometry())
        flow.indexResult(input, frame: input.frame, captureTime: input.captureTime, now: input.captureTime, geometry: try geometry())
    }

    // Break caught: cursor motion is accumulated automatically or pending Vision callbacks cross Start.
    func testStartArmsOnlyFutureIndexAndFinishRequiresSeparateAcceptance() throws {
        var flow = try flow()
        try deliver(&flow, input(0, time: 0.9))
        XCTAssertTrue(flow.rawTrace.isEmpty)
        flow.startDrawing(at: 1, geometry: try geometry())
        let old = input(0, time: 0.99)
        flow.recordSource(frame: old.frame, captureTime: old.captureTime, now: 1.01, geometry: try geometry())
        flow.indexResult(old, frame: old.frame, captureTime: old.captureTime, now: 1.01, geometry: try geometry())
        XCTAssertEqual(flow.state, .armed)
        XCTAssertTrue(flow.rawTrace.isEmpty)
        for i in 0...24 { try deliver(&flow, input(i)) }
        XCTAssertEqual(flow.rawTrace.count, 25)
        flow.finishDrawing(now: 1.26, geometry: try geometry())
        XCTAssertEqual(flow.state, .candidateReady)
        XCTAssertNil(flow.session.reviewedRegion)
        flow.indexResult(nil, frame: input(25).frame, captureTime: 1.27, now: 1.27, geometry: try geometry())
        XCTAssertEqual(flow.rawTrace.count, 25)
        XCTAssertNotNil(try flow.accept())
    }

    // Break caught: a fresh index is paired with a different frame or a fabricated capture time.
    func testIndexMustMatchActualSourceFrameAndCaptureTime() throws {
        for variant in 0..<3 {
            var flow = try flow()
            flow.startDrawing(at: 1, geometry: try geometry())
            try deliver(&flow, input(0))
            let next = input(1)
            if variant != 0 {
                flow.recordSource(frame: next.frame, captureTime: variant == 1 ? 1.019 : next.captureTime,
                                  now: next.captureTime, geometry: try geometry())
            }
            flow.indexResult(next, frame: variant == 2 ? input(2).frame : next.frame,
                             captureTime: next.captureTime, now: next.captureTime, geometry: try geometry())
            // Tolerant index drawing: the unmatched result is skipped (never drawn), not fatal.
            XCTAssertEqual(flow.state, .tracing)
            XCTAssertEqual(flow.rawTrace.count, 1, "a mismatched frame must never add a point")
        }
    }
}
