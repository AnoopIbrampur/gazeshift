import XCTest
@testable import GazeShiftCore

final class GazeShiftCoreTests: XCTestCase {
    // Break caught: accepting geometry that cannot produce finite buffer coordinates.
    func testGeometryRejectsInvalidOrOverflowingDimensionsAndChecksBounds() throws {
        for dimensions in [(0.0, 400.0, 2.0), (300, -1, 2), (300, 400, .nan),
                           (.greatestFiniteMagnitude, .greatestFiniteMagnitude, 2)] {
            XCTAssertThrowsError(try RenderGeometry(width: dimensions.0, height: dimensions.1,
                                                    scale: dimensions.2, orientation: .portrait,
                                                    mode: .frontSetup, viewingSetupID: "fixed"))
        }
        let g = try geometry()
        XCTAssertTrue(g.contains(ScreenPoint(x: 0, y: 400)))
        XCTAssertFalse(g.contains(ScreenPoint(x: .nan, y: 2)))
        XCTAssertFalse(g.contains(ScreenPoint(x: 301, y: 2)))
        XCTAssertEqual(HeldOutTarget.upperLeft.normalized, ScreenPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(HeldOutTarget.lowerRight.normalized, ScreenPoint(x: 0.75, y: 0.75))
    }

    private func geometry() throws -> RenderGeometry {
        try RenderGeometry(width: 300, height: 400, scale: 2, orientation: .portrait,
                           mode: .frontSetup, viewingSetupID: "seated-40cm")
    }

    // Break caught: fitting with wrong axis/sign or a target-dependent prediction.
    func testKnownMappingPredictsUnseenFeaturesAndRejectsGeometryChanges() throws {
        let g = try geometry()
        let model = try fitted(g)
        let point = try model.predict(features: EyeFeatures(horizontal: 0.3, vertical: -0.4), geometry: g)
        XCTAssertEqual(point.x, 156, accuracy: 0.001)
        XCTAssertEqual(point.y, 169, accuracy: 0.001)
        let changed = try RenderGeometry(width: 300, height: 400, scale: 3, orientation: .portrait,
                                         mode: .frontSetup, viewingSetupID: "seated-40cm")
        XCTAssertThrowsError(try model.predict(features: EyeFeatures(horizontal: 0, vertical: 0), geometry: changed))
        XCTAssertEqual(g.normalized(ScreenPoint(x: 75, y: 300)), ScreenPoint(x: 0.25, y: 0.75))
        XCTAssertEqual(g.pixels(ScreenPoint(x: 75, y: 300)), ScreenPoint(x: 150, y: 600))
    }

    // Break caught: treating raw lookAtPoint as screen gaze or dividing by near-zero z.
    func testEyeDirectionUsesMidpointAndRejectsUnsafeOrNonfiniteInputs() throws {
        let features = try EyeFeatures.from(leftEye: SIMD3(-1, 0, 1), rightEye: SIMD3(1, 0, 1),
                                            lookAtPoint: SIMD3(2, -3, 3))
        XCTAssertEqual(features.horizontal, 1)
        XCTAssertEqual(features.vertical, -1.5)
        XCTAssertThrowsError(try EyeFeatures.from(leftEye: .zero, rightEye: .zero,
                                                  lookAtPoint: SIMD3(1, 1, 0)))
        XCTAssertThrowsError(try EyeFeatures(horizontal: .nan, vertical: 0))
        XCTAssertThrowsError(try EyeFeatures.from(leftEye: SIMD3(.infinity, 0, 0), rightEye: .zero,
                                                  lookAtPoint: SIMD3(0, 0, 1)))
    }

    // Break caught: ridge disguising a degenerate calibration as a usable fit.
    func testCalibrationRejectsInsufficientCollinearAndNonfiniteLabels() throws {
        let g = try geometry()
        XCTAssertThrowsError(try GazeCalibration.fit(samples: [], geometry: g))
        let collinear = try (-4...4).map { i in
            CalibrationSample(features: try EyeFeatures(horizontal: Double(i), vertical: Double(i)),
                              target: ScreenPoint(x: 150 + Double(i), y: 200 + Double(i)))
        }
        XCTAssertThrowsError(try GazeCalibration.fit(samples: collinear, geometry: g))
        var bad = try trainingSamples()
        bad[0] = CalibrationSample(features: bad[0].features, target: ScreenPoint(x: .nan, y: 5))
        XCTAssertThrowsError(try GazeCalibration.fit(samples: bad, geometry: g))
    }

    // Break caught: a finite off-screen estimate being clamped or discarded from accuracy.
    func testOffscreenPredictionsRemainInScoringButNotLiveDisplay() throws {
        let g = try geometry()
        let model = try fitted(g)
        let f = try EyeFeatures(horizontal: 20, vertical: 0)
        let raw = try model.predict(features: f, geometry: g)
        XCTAssertGreaterThan(raw.x, 300)
        XCTAssertNil(model.livePrediction(observation: observation(f, time: 1), now: 1, geometry: g))
        var window = try HeldOutWindow(target: .upperLeft, pass: 1, presentedAt: 0, geometry: g)
        for i in 0..<20 {
            let time = 0.5 + Double(i) * 0.05 + 0.001
            try window.record(slot: i, now: time, observation: observation(f, time: time), calibration: model)
        }
        let result = window.finish()
        XCTAssertEqual(result.validPredictions, 20)
        XCTAssertEqual(result.receivedUniqueSamples, 20)
        XCTAssertGreaterThan(try XCTUnwrap(result.errors).medianPoints, 300)
        XCTAssertFalse(result.passesNumericalGate)
    }

    // Break caught: extending windows, reusing timestamps, or allowing blink/stale data.
    func testFixedWindowCountsDuplicatesStaleBlinkMissingAndOutOfWindow() throws {
        let g = try geometry()
        let model = try fitted(g)
        let f = try EyeFeatures(horizontal: 0, vertical: 0)
        var window = try HeldOutWindow(target: .upperLeft, pass: 1, presentedAt: 10, geometry: g)
        try window.record(slot: 0, now: 10.501, observation: observation(f, time: 10.501), calibration: model)
        try window.record(slot: 1, now: 10.551, observation: observation(f, time: 10.501), calibration: model)
        try window.record(slot: 6, now: 10.801, observation: observation(f, time: 10.51), calibration: model)
        try window.record(slot: 7, now: 10.851, observation: observation(f, time: 10.851, blink: 0.6), calibration: model)
        try window.record(slot: 8, now: 10.901, observation: observation(f, time: 10.4), calibration: model)
        try window.record(slot: 19, now: 11.6, observation: observation(f, time: 11.6), calibration: model)
        XCTAssertThrowsError(try window.record(slot: 20, now: 11.5, observation: nil, calibration: model))
        let result = window.finish()
        XCTAssertEqual(result.expectedSlots, 20)
        XCTAssertEqual(result.validPredictions, 1)
        XCTAssertEqual(result.rejectedSlots, 19)
        XCTAssertEqual(result.rejectionCounts[.duplicate], 1)
        XCTAssertEqual(result.rejectionCounts[.stale], 1)
        XCTAssertEqual(result.rejectionCounts[.closedEyes], 1)
        XCTAssertEqual(result.rejectionCounts[.outsideWindow], 1)
        XCTAssertEqual(result.rejectionCounts[.missedSchedule], 1)
        XCTAssertEqual(result.rejectionCounts[.missing], 14)
    }

    // Break caught: accepting absent quality/future/untracked data as a valid live gaze.
    func testLiveQualityRequiresCompleteFreshTrackedOpenEyeData() throws {
        let g = try geometry()
        let model = try fitted(g)
        let f = try EyeFeatures(horizontal: 0, vertical: 0)
        XCTAssertNotNil(model.livePrediction(observation: observation(f, time: 1), now: 1.25, geometry: g))
        XCTAssertNil(model.livePrediction(observation: observation(f, time: 1), now: 1.251, geometry: g))
        XCTAssertNil(model.livePrediction(observation: observation(f, time: 2), now: 1, geometry: g))
        XCTAssertNil(model.livePrediction(observation: GazeObservation(timestamp: 1, isTracked: false, leftBlink: 0, rightBlink: 0, features: f), now: 1, geometry: g))
        XCTAssertNil(model.livePrediction(observation: GazeObservation(timestamp: 1, isTracked: true, leftBlink: nil, rightBlink: 0, features: f), now: 1, geometry: g))
        XCTAssertNil(model.livePrediction(observation: GazeObservation(timestamp: 1, isTracked: true, leftBlink: 0, rightBlink: 0, features: nil), now: 1, geometry: g))
        XCTAssertNil(model.livePrediction(observation: observation(f, time: .nan), now: 1, geometry: g))
        XCTAssertNil(model.livePrediction(observation: observation(f, time: 1, blink: .nan), now: 1, geometry: g))
        XCTAssertNil(model.livePrediction(observation: observation(f, time: 1), now: .nan, geometry: g))
    }

    // Break caught: aggregate success concealing a bad target or a missing target window.
    func testHeldOutReportRequiresEveryWindowAndSeparatesCenterAndEyeOnlyEvidence() throws {
        let g = try geometry()
        let model = try fitted(g)
        var results: [HeldOutWindowResult] = []
        for pass in 1...2 {
            for target in HeldOutTarget.novelTargets {
                results.append(try successfulWindow(target: target, pass: pass, model: model, geometry: g))
            }
        }
        let missing = try HeldOutReport(windows: Array(results.dropLast()), geometry: g)
        XCTAssertFalse(missing.passesNumericalGate)
        XCTAssertEqual(missing.novelWindows.count, 8)
        XCTAssertEqual(missing.novelWindows.last?.rejectedSlots, 20)
        let center = try successfulWindow(target: .centerControl, pass: 1, model: model, geometry: g)
        let complete = try HeldOutReport(windows: results + [center], geometry: g)
        XCTAssertTrue(complete.passesNumericalGate)
        XCTAssertFalse(complete.passesCompleteGate)
        XCTAssertEqual(complete.overallValidPredictions, 160)
        XCTAssertEqual(complete.centerControls.count, 1)
        XCTAssertTrue(try HeldOutReport(windows: results, geometry: g, eyeOnlyResponse: .observedPass).passesCompleteGate)
        XCTAssertThrowsError(try HeldOutReport(windows: results + [results[0]], geometry: g))
    }

    // Break caught: meeting coverage by collecting after the declared 1-second window.
    func testExactlySixteenOfTwentyPassesCoverageAndFifteenFails() throws {
        let g = try geometry()
        let model = try fitted(g)
        XCTAssertTrue(try successfulWindow(target: .lowerRight, pass: 2, model: model, geometry: g, count: 16).passesNumericalGate)
        let failed = try successfulWindow(target: .lowerRight, pass: 2, model: model, geometry: g, count: 15)
        XCTAssertFalse(failed.passesNumericalGate)
        XCTAssertEqual(failed.validFraction, 0.75)
        XCTAssertEqual(failed.rejectedSlots, 5)
    }

    // Break caught: reusing a scheduled slot or inventing invalid target/pass windows.
    func testWindowRejectsDuplicateSlotAndInvalidWindowMetadata() throws {
        let g = try geometry()
        let model = try fitted(g)
        XCTAssertThrowsError(try HeldOutWindow(target: .upperLeft, pass: 0, presentedAt: 0, geometry: g))
        XCTAssertThrowsError(try HeldOutWindow(target: .upperLeft, pass: 1, presentedAt: .nan, geometry: g))
        var window = try HeldOutWindow(target: .upperLeft, pass: 1, presentedAt: 0, geometry: g)
        try window.record(slot: 0, now: 0.501, observation: nil, calibration: model)
        XCTAssertThrowsError(try window.record(slot: 0, now: 0.502, observation: nil, calibration: model))
        XCTAssertEqual(window.finish().rejectionCounts[.missing], 20)
    }

    private func trainingSamples() throws -> [CalibrationSample] {
        try [-1.0, 0, 1].flatMap { h in
            try [-1.0, 0, 1].map { v in
                CalibrationSample(features: try EyeFeatures(horizontal: h, vertical: v),
                                  target: ScreenPoint(x: 150 + 100 * h + 60 * v,
                                                      y: 200 + 30 * h + 100 * v))
            }
        }
    }
    private func fitted(_ g: RenderGeometry) throws -> GazeCalibration {
        try GazeCalibration.fit(samples: trainingSamples(), geometry: g)
    }
    private func observation(_ f: EyeFeatures, time: Double, blink: Double = 0) -> GazeObservation {
        GazeObservation(timestamp: time, isTracked: true, leftBlink: blink, rightBlink: blink, features: f)
    }
    private func successfulWindow(target: HeldOutTarget, pass: Int, model: GazeCalibration,
                                  geometry: RenderGeometry, count: Int = 20) throws -> HeldOutWindowResult {
        var window = try HeldOutWindow(target: target, pass: pass, presentedAt: 0, geometry: geometry)
        // Independent inverse of x=150+100h+60v, y=200+30h+100v.
        let x = target.normalized.x * 300 - 150
        let y = target.normalized.y * 400 - 200
        let f = try EyeFeatures(horizontal: (100 * x - 60 * y) / 8200,
                                vertical: (-30 * x + 100 * y) / 8200)
        for i in 0..<count {
            let time = 0.5 + Double(i) * 0.05 + 0.001
            try window.record(slot: i, now: time, observation: observation(f, time: time), calibration: model)
        }
        return window.finish()
    }
}
