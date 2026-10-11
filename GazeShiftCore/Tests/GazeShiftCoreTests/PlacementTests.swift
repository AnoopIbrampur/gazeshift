import XCTest
@testable import GazeShiftCore

final class PlacementTests: XCTestCase {
    // Break caught: losing fixation offset or translating the wrong source rectangle.
    func testPlacementPreservesOffsetAndCopiesOneOriginalSourceRectangle() throws {
        let g = try geometry()
        let result = PlacementPlanner.plan(region: try reviewedRegion(), gaze: ScreenPoint(x: 160, y: 210), geometry: g, userOffset: ScreenPoint(x: 130, y: 0), liveMargin: LivePlacementMargin(p90ErrorPoints: 10, geometry: g, validated: true), cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: 300, height: 400))
        guard case let .accepted(placement) = result else { return XCTFail("Expected valid original-frame copy") }
        XCTAssertEqual(placement.ellipse.center.x, 120, accuracy: 0.000001)
        XCTAssertEqual(placement.ellipse.center.y, 140, accuracy: 0.000001)
        XCTAssertEqual(placement.source.x, 90, accuracy: 0.000001)
        XCTAssertEqual(placement.source.y, 120, accuracy: 0.000001)
        XCTAssertEqual(placement.source.width, 60, accuracy: 0.000001)
        XCTAssertEqual(placement.source.height, 40, accuracy: 0.000001)
        XCTAssertEqual(placement.destination.x, 220, accuracy: 0.000001)
        XCTAssertEqual(placement.destination.y, 120, accuracy: 0.000001)
        XCTAssertEqual(placement.samplingSource, .originalFrame)
        XCTAssertEqual(placement.safetyGapPoints, 10)
    }

    // Break caught: permitting partial crops or clamping to viewport/camera edges.
    func testRejectsSourceAndDestinationOutsideViewportAndSamplingBounds() throws {
        XCTAssertEqual(try rejection(gaze: ScreenPoint(x: 40, y: 200)), .sourceOutsideBounds)
        XCTAssertEqual(try rejection(offset: ScreenPoint(x: 200, y: 0)), .destinationOutsideBounds)
        XCTAssertEqual(try rejection(bounds: ScreenRect(x: 100, y: 0, width: 200, height: 400)), .sourceOutsideBounds)
        XCTAssertEqual(try rejection(bounds: ScreenRect(x: 0, y: 0, width: 250, height: 400)), .destinationOutsideBounds)
        XCTAssertEqual(try rejection(bounds: ScreenRect(x: .nan, y: 0, width: 300, height: 400)), .invalidSamplingBounds)
        XCTAssertEqual(try rejection(bounds: ScreenRect(x: 0, y: 0, width: 0, height: 400)), .invalidSamplingBounds)
    }

    // Break caught: accepting overlap or ignoring the measured live p90 safety gap.
    func testOverlapAndP90GapRejectWithoutSearchingForAnotherOffset() throws {
        XCTAssertEqual(try rejection(offset: ScreenPoint(x: 0, y: 0)), .destinationOverlapsRegion)
        XCTAssertEqual(try rejection(offset: ScreenPoint(x: 65, y: 0)), .destinationOverlapsRegion)
        XCTAssertEqual(try rejection(offset: ScreenPoint(x: 70, y: 0)), .destinationOverlapsRegion)
        let g = try geometry()
        let valid = PlacementPlanner.plan(region: try reviewedRegion(), gaze: ScreenPoint(x: 160, y: 210), geometry: g, userOffset: ScreenPoint(x: 71, y: 0), liveMargin: LivePlacementMargin(p90ErrorPoints: 10, geometry: g, validated: true), cameraSamplingBounds: fullBounds)
        guard case let .accepted(p) = valid else { return XCTFail("A destination clearing the measured margin must fit") }
        XCTAssertEqual(p.destination.x, 161, accuracy: 0.000001)
    }

    // Break caught: an absent/unvalidated/wrong-mode or nonfinite error margin enabling copies.
    func testRequiresValidatedFiniteMarginForExactLiveGeometry() throws {
        let g = try geometry()
        let missing = PlacementPlanner.plan(region: try reviewedRegion(), gaze: ScreenPoint(x: 160, y: 210), geometry: g, userOffset: ScreenPoint(x: 130, y: 0), liveMargin: nil, cameraSamplingBounds: fullBounds)
        XCTAssertEqual(missing, .rejected(.unvalidatedLiveMargin))
        for value in [-1.0, .infinity, .nan] {
            XCTAssertEqual(try rejection(margin: LivePlacementMargin(p90ErrorPoints: value, geometry: g, validated: true)), .unvalidatedLiveMargin)
        }
        XCTAssertEqual(try rejection(margin: LivePlacementMargin(p90ErrorPoints: 10, geometry: g, validated: false)), .unvalidatedLiveMargin)
        let front = try geometry(mode: .frontSetup)
        XCTAssertEqual(try rejection(margin: LivePlacementMargin(p90ErrorPoints: 10, geometry: front, validated: true)), .unvalidatedLiveMargin)
    }

    // Break caught: nonfinite/offscreen gaze or user offsets causing invalid rectangle math.
    func testRejectsNonfiniteOffscreenGazeAndOffsetAndChangedRegionGeometry() throws {
        for gaze in [ScreenPoint(x: .nan, y: 200), ScreenPoint(x: 150, y: .infinity), ScreenPoint(x: -1, y: 200)] {
            XCTAssertEqual(try rejection(gaze: gaze), .invalidGaze)
        }
        XCTAssertEqual(try rejection(offset: ScreenPoint(x: .infinity, y: 0)), .invalidOffset)
        let changed = try RenderGeometry(width: 300, height: 400, scale: 3, orientation: .portrait, mode: .rearLive, viewingSetupID: "seated-40cm")
        let result = PlacementPlanner.plan(region: try reviewedRegion(), gaze: ScreenPoint(x: 160, y: 210), geometry: changed, userOffset: ScreenPoint(x: 130, y: 0), liveMargin: LivePlacementMargin(p90ErrorPoints: 10, geometry: changed, validated: true), cameraSamplingBounds: fullBounds)
        XCTAssertEqual(result, .rejected(.regionGeometryChanged))
        XCTAssertEqual(result.statusText, "No valid placement — original view")
    }

    private let fullBounds = ScreenRect(x: 0, y: 0, width: 300, height: 400)
    private func geometry(mode: TrackingMode = .rearLive) throws -> RenderGeometry {
        try RenderGeometry(width: 300, height: 400, scale: 2, orientation: .portrait, mode: mode, viewingSetupID: "seated-40cm")
    }
    private func reviewedRegion() throws -> ReviewedRegion {
        var session = try AirTraceSession(geometry: geometry(mode: .frontSetup), fixation: ScreenPoint(x: 150, y: 200), eyeStateDescription: "binocular-open", captureGeneration: 1)
        for i in 0...24 {
            let angle = Double(i % 24) * 2 * .pi / 24
            let point = ScreenPoint(x: 110 + 30 * cos(angle), y: 130 + 20 * sin(angle))
            let time = 1 + Double(i) * 0.01
            let hand = AirTraceHandSample(indexTip: point, thumbTip: ScreenPoint(x: point.x + (i == 24 ? 40 : 1), y: point.y), indexConfidence: 1, thumbConfidence: 1, captureTimestamp: time, generation: 1)
            let gaze = AirTraceGazeSample(point: ScreenPoint(x: 150, y: 200), qualityValid: true, captureTimestamp: time, generation: 1)
            session.consume(hand: hand, gaze: gaze, now: time, geometry: try geometry(mode: .frontSetup))
        }
        return try session.acceptCandidate().retainedForModeTransition(to: geometry())
    }
    private func rejection(gaze: ScreenPoint = ScreenPoint(x: 160, y: 210), offset: ScreenPoint = ScreenPoint(x: 130, y: 0), margin: LivePlacementMargin? = nil, bounds: ScreenRect? = nil) throws -> PlacementRejection? {
        let g = try geometry()
        let defaultMargin = LivePlacementMargin(p90ErrorPoints: 10, geometry: g, validated: true)
        let result = PlacementPlanner.plan(region: try reviewedRegion(), gaze: gaze, geometry: g, userOffset: offset, liveMargin: margin ?? defaultMargin, cameraSamplingBounds: bounds ?? fullBounds)
        if case let .rejected(reason) = result { return reason }
        return nil
    }
}
