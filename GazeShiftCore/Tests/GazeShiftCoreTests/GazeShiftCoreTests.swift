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
        let results = try successfulProtocol(model: model, geometry: g)
        let missing = try HeldOutReport(windows: Array(results.dropLast()), geometry: g)
        XCTAssertFalse(missing.passesNumericalGate)
        XCTAssertEqual(missing.novelWindows.count, 8)
        XCTAssertEqual(missing.novelWindows.last?.rejectedSlots, 20)
        let complete = try HeldOutReport(windows: results, geometry: g)
        XCTAssertTrue(complete.passesNumericalGate)
        XCTAssertTrue(complete.passesProtocolGate)
        XCTAssertFalse(complete.passesCompleteGate)
        XCTAssertEqual(complete.overallValidPredictions, 160)
        XCTAssertEqual(complete.centerControls.count, 2)
        XCTAssertTrue(try HeldOutReport(windows: results, geometry: g, eyeOnlyResponse: .observedPass).passesCompleteGate)
        XCTAssertThrowsError(try HeldOutReport(windows: results + [results[0]], geometry: g))
    }

    // Break caught: declaring completion without a measured center repeat in each pass.
    func testCompletionRejectsMissingOrInsufficientCenterControls() throws {
        let g = try geometry()
        let model = try fitted(g)
        let full = try successfulProtocol(model: model, geometry: g)
        for missingPass in [0, 1, 2] {
            let windows = full.filter { $0.target != .centerControl || (missingPass != 0 && $0.pass != missingPass) }
            let report = try HeldOutReport(windows: windows, geometry: g, eyeOnlyResponse: .observedPass)
            XCTAssertTrue(report.passesNumericalGate)
            XCTAssertFalse(report.passesCompleteGate)
            XCTAssertEqual(report.overallValidPredictions, 160)
        }
        var insufficient = full
        insufficient[2] = try successfulWindow(target: .centerControl, pass: 1, model: model,
                                               geometry: g, count: 15, presentedAt: 14)
        XCTAssertFalse(try HeldOutReport(windows: insufficient, geometry: g,
                                        eyeOnlyResponse: .observedPass).passesCompleteGate)
    }

    // Break caught: accepting both controls even when neither repeats between novel targets.
    func testCompletionRejectsCenterBeforeOrAfterItsPass() throws {
        let g = try geometry()
        let model = try fitted(g)
        for centerTime in [8.0, 20.0] {
            var windows = try successfulProtocol(model: model, geometry: g)
            windows[2] = try successfulWindow(target: .centerControl, pass: 1, model: model,
                                             geometry: g, presentedAt: centerTime)
            let report = try HeldOutReport(windows: windows, geometry: g, eyeOnlyResponse: .observedPass)
            XCTAssertTrue(report.passesNumericalGate)
            XCTAssertFalse(report.passesCompleteGate)
        }
    }

    // Break caught: reusing simultaneous windows, changing target during evaluation, or reversing passes.
    func testCompletionRejectsOverlappingPresentationsAndReversedPasses() throws {
        let g = try geometry()
        let model = try fitted(g)
        for nextPresentation in [10.5, 11.25] {
            var windows = try successfulProtocol(model: model, geometry: g)
            windows[1] = try successfulWindow(target: .upperRight, pass: 1, model: model,
                                             geometry: g, presentedAt: nextPresentation)
            XCTAssertFalse(try HeldOutReport(windows: windows, geometry: g,
                                            eyeOnlyResponse: .observedPass).passesCompleteGate)
        }
        let reversedPasses = try successfulProtocol(model: model, geometry: g, passBases: [30, 10])
        XCTAssertFalse(try HeldOutReport(windows: reversedPasses, geometry: g,
                                        eyeOnlyResponse: .observedPass).passesCompleteGate)
    }

    // Break caught: confusing collection-array order with actual presentation chronology.
    func testValidInterleavedProtocolUsesTimingAndKeepsPhysicalEvidenceExplicit() throws {
        let g = try geometry()
        let model = try fitted(g)
        let windows = Array(try successfulProtocol(model: model, geometry: g).reversed())
        let firstPresentation = try XCTUnwrap(windows.first(where: { $0.pass == 1 && $0.target == .upperLeft }))
        XCTAssertEqual(firstPresentation.presentedAt, 10)
        XCTAssertEqual(firstPresentation.startsAt, 10.5)
        XCTAssertEqual(firstPresentation.endsAt, 11.5)
        XCTAssertTrue(try HeldOutReport(windows: windows, geometry: g,
                                       eyeOnlyResponse: .observedPass).passesCompleteGate)
        XCTAssertFalse(try HeldOutReport(windows: windows, geometry: g).passesCompleteGate)
        XCTAssertFalse(try HeldOutReport(windows: windows, geometry: g,
                                        eyeOnlyResponse: .observedFail).passesCompleteGate)
    }

    // Break caught: a poor training-location control affecting novel-position error statistics.
    func testCenterErrorsStaySeparateFromNovelStatistics() throws {
        let g = try geometry()
        let model = try fitted(g)
        var windows = try successfulProtocol(model: model, geometry: g)
        var center = try HeldOutWindow(target: .centerControl, pass: 1, presentedAt: 14, geometry: g)
        let offscreen = try EyeFeatures(horizontal: 20, vertical: 0)
        for slot in 0..<20 {
            let time = 14.5 + Double(slot) * 0.05 + 0.001
            try center.record(slot: slot, now: time, observation: observation(offscreen, time: time), calibration: model)
        }
        windows[2] = center.finish()
        let report = try HeldOutReport(windows: windows, geometry: g)
        XCTAssertTrue(report.passesNumericalGate)
        XCTAssertTrue(report.passesProtocolGate)
        XCTAssertEqual(report.overallValidPredictions, 160)
        XCTAssertLessThan(try XCTUnwrap(report.overallErrors).p90Points, 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(report.centerControls[0].errors).medianPoints, 300)
        XCTAssertFalse(report.passesCompleteGate)
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

    // Break caught: erasing error direction or summarizing received/rejected features as accepted data.
    func testAcceptedWindowDiagnosticsKeepSignedMediansAndRawPopulationSpread() throws {
        let g = try geometry()
        let model = try fitted(g)
        let features = try [(0.0, 0.0), (1, -1), (2, 1), (3, -2)].map {
            try EyeFeatures(horizontal: $0.0, vertical: $0.1)
        }
        for (target, count, dx, dy) in [(HeldOutTarget.upperLeft, 4, 185.0, 65.0), (.lowerRight, 4, 35, -135),
                                      (.lowerRight, 3, -35, -100)] {
            var window = try HeldOutWindow(target: target, pass: 1, presentedAt: 0, geometry: g)
            for (slot, feature) in features.prefix(count).enumerated() {
                let time = 0.501 + Double(slot) * 0.05
                try window.record(slot: slot, now: time, observation: observation(feature, time: time), calibration: model)
            }
            let rejected = try EyeFeatures(horizontal: 100, vertical: 100)
            try window.record(slot: 4, now: 0.701,
                              observation: observation(rejected, time: 0.701, blink: 0.8), calibration: model)
            let result = window.finish()
            XCTAssertEqual(result.validPredictions, count, "Finite off-screen predictions remain accepted")
            XCTAssertEqual(result.receivedUniqueSamples, count + 1)
            XCTAssertEqual(result.rejectedSlots, 20 - count)
            XCTAssertEqual(result.rejectionCounts[.closedEyes], 1)
            XCTAssertEqual(try XCTUnwrap(result.medianDXPoints), dx, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(result.medianDYPoints), dy, accuracy: 0.001)
            let summary = try XCTUnwrap(result.featureSummary)
            if count == 4 {
                XCTAssertEqual(summary.horizontalMean, 1.5, accuracy: 1e-12)
                XCTAssertEqual(summary.verticalMean, -0.5, accuracy: 1e-12)
                XCTAssertEqual(summary.horizontalPopulationSD, 1.118033988749895, accuracy: 1e-12)
                XCTAssertEqual(summary.verticalPopulationSD, 1.118033988749895, accuracy: 1e-12)
            } else {
                XCTAssertEqual(summary.horizontalMean, 1, accuracy: 1e-12)
                XCTAssertEqual(summary.verticalMean, 0, accuracy: 1e-12)
                XCTAssertEqual(summary.horizontalPopulationSD, 0.816496580927726, accuracy: 1e-12)
                XCTAssertEqual(summary.verticalPopulationSD, 0.816496580927726, accuracy: 1e-12)
            }
        }
    }

    // Break caught: invented zero diagnostics for an unmeasured window or nonfinite public summary.
    func testDiagnosticsAreUnavailableForEmptyWindowsAndFiniteForExtremeFeatures() throws {
        let g = try geometry()
        let empty = try HeldOutWindow(target: .upperLeft, pass: 1, presentedAt: 0, geometry: g).finish()
        let missing = try HeldOutReport(windows: [], geometry: g).novelWindows
        for result in [empty] + missing {
            XCTAssertNil(result.medianDXPoints)
            XCTAssertNil(result.medianDYPoints)
            XCTAssertNil(result.featureSummary)
        }
        XCTAssertNil(EyeFeatureSummary(features: []))
        let extremes = try [-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude].map {
            try EyeFeatures(horizontal: $0, vertical: 2)
        }
        let summary = try XCTUnwrap(EyeFeatureSummary(features: extremes))
        XCTAssertEqual(summary.horizontalMean, 0)
        XCTAssertEqual(summary.horizontalPopulationSD, Double.greatestFiniteMagnitude)
        XCTAssertEqual(summary.verticalMean, 2)
        XCTAssertEqual(summary.verticalPopulationSD, 0)
        let single = try XCTUnwrap(EyeFeatureSummary(features: [EyeFeatures(horizontal: -3, vertical: 4)]))
        XCTAssertEqual(single.horizontalMean, -3)
        XCTAssertEqual(single.verticalMean, 4)
        XCTAssertEqual(single.horizontalPopulationSD, 0)
        XCTAssertEqual(single.verticalPopulationSD, 0)
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
                                  geometry: RenderGeometry, count: Int = 20,
                                  presentedAt: Double = 0) throws -> HeldOutWindowResult {
        var window = try HeldOutWindow(target: target, pass: pass, presentedAt: presentedAt, geometry: geometry)
        // Independent inverse of x=150+100h+60v, y=200+30h+100v.
        let x = target.normalized.x * 300 - 150
        let y = target.normalized.y * 400 - 200
        let f = try EyeFeatures(horizontal: (100 * x - 60 * y) / 8200,
                                vertical: (-30 * x + 100 * y) / 8200)
        for i in 0..<count {
            let time = presentedAt + 0.5 + Double(i) * 0.05 + 0.001
            try window.record(slot: i, now: time, observation: observation(f, time: time), calibration: model)
        }
        return window.finish()
    }

    private func successfulProtocol(model: GazeCalibration, geometry: RenderGeometry,
                                    passBases: [Double] = [10, 30]) throws -> [HeldOutWindowResult] {
        // Hand-specified sequence: five 1.5-second presentations, spaced two seconds apart.
        let targets: [HeldOutTarget] = [.upperLeft, .upperRight, .centerControl, .lowerLeft, .lowerRight]
        var windows: [HeldOutWindowResult] = []
        for (passIndex, base) in passBases.enumerated() {
            for (index, target) in targets.enumerated() {
                windows.append(try successfulWindow(target: target, pass: passIndex + 1,
                                                    model: model, geometry: geometry,
                                                    presentedAt: base + Double(index) * 2))
            }
        }
        return windows
    }
}
