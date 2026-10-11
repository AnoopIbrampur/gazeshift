import XCTest
import GazeShiftCore
@testable import GazeShiftFlow

final class ScreenTouchTraceFlowTests: XCTestCase {
    private func geometry() throws -> RenderGeometry {
        try RenderGeometry(width: 400, height: 300, scale: 3, orientation: .landscapeLeft,
                           mode: .rearLive, viewingSetupID: "touch-flow")
    }
    private func flow() throws -> AirTraceFlow {
        AirTraceFlow(session: try AirTraceSession(screenTouchGeometry: geometry(), captureGeneration: 1))
    }
    private func source(_ flow: inout AirTraceFlow, at time: Double, generation: UInt64 = 1) throws {
        flow.recordSource(frame: CaptureFrameKey(generation: generation, frameTimestamp: time),
                          captureTime: time, now: time, geometry: try geometry())
    }

    // Actual screen points use their UI clock, without invented frame keys or hand confidence, and preserve review/Accept.
    func testRearTouchFlowUsesActualSourceAndSeparateAcceptance() throws {
        var flow = try flow()
        flow.startDrawing(at: 1, geometry: try geometry())
        flow.touchPoint(ScreenPoint(x: 150, y: 140), now: 1.01, geometry: try geometry())
        XCTAssertTrue(flow.rawTrace.isEmpty)
        for i in 0...24 {
            let time = 1.01 + Double(i) * 0.01
            let angle = Double(i % 24) * 2 * .pi / 24
            try source(&flow, at: time)
            flow.touchPoint(ScreenPoint(x: 120 + 30 * cos(angle), y: 140 + 20 * sin(angle)),
                            now: time, geometry: try geometry())
        }
        flow.finishDrawing(now: 1.26, geometry: try geometry())
        XCTAssertEqual(flow.state, .candidateReady)
        XCTAssertNil(flow.session.reviewedRegion)
        XCTAssertEqual(flow.candidateEllipse?.center, ScreenPoint(x: 120, y: 140))
        XCTAssertEqual(flow.candidateEllipse?.radii, ScreenPoint(x: 30, y: 20))
        XCTAssertNotNil(try flow.accept())
        XCTAssertEqual(flow.state, .accepted)
    }

    // The watchdog rejects stopped capture even if touches keep arriving; Redo needs a new source event.
    func testSourceLossClearsTouchAndRedoRequiresNewCameraEvent() throws {
        var flow = try flow()
        flow.startDrawing(at: 1, geometry: try geometry())
        try source(&flow, at: 1.01)
        flow.touchPoint(ScreenPoint(x: 150, y: 140), now: 1.01, geometry: try geometry())
        flow.expireInputs(now: 1.4, geometry: try geometry())
        XCTAssertEqual(flow.state, .invalid(.stalePair))
        XCTAssertTrue(flow.rawTrace.isEmpty)
        flow.redo()
        flow.startDrawing(at: 1.5, geometry: try geometry())
        flow.touchPoint(ScreenPoint(x: 150, y: 140), now: 1.51, geometry: try geometry())
        XCTAssertEqual(flow.state, .armed)
        XCTAssertTrue(flow.rawTrace.isEmpty)
        try source(&flow, at: 1.52)
        flow.touchPoint(ScreenPoint(x: 150, y: 140), now: 1.52, geometry: try geometry())
        XCTAssertEqual(flow.state, .tracing)
        try source(&flow, at: 1.53, generation: 2)
        XCTAssertEqual(flow.state, .invalid(.generationChanged))
        XCTAssertTrue(flow.rawTrace.isEmpty)
    }
}
