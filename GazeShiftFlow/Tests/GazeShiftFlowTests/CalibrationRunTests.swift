import Testing
import GazeShiftCore
@testable import GazeShiftFlow

@Suite("Calibration run (fixtures)")
struct CalibrationRunTests {
    /// Fixture eye that looks exactly at whatever target is currently shown.
    static func idealObservation(_ phase: CalibrationRunPhase, _ now: Double) -> GazeObservation? {
        switch phase {
        case let .training(_, _, target, _, _): Fixture.observation(at: now, looking: target)
        case let .heldOut(_, _, _, _, point, _, _): Fixture.observation(at: now, looking: point)
        default: nil
        }
    }

    static func run(_ run: inout CalibrationRun, trainingRate: Double = 60, heldOutRate: Double = 60,
                    observation: (CalibrationRunPhase, Double) -> GazeObservation? = idealObservation) {
        var now = 10.0
        run.start(now: now)
        while now < 100 {
            switch run.phase {
            case .training: now += 1 / trainingRate
            case .heldOut: now += 1 / heldOutRate
            default: return
            }
            run.tick(now: now, observation: observation(run.phase, now), geometry: run.geometry)
        }
    }

    @Test func idealFixtureRunPassesCompleteGateOnlyAfterEyeOnlyCheck() throws {
        var calibration = CalibrationRun(geometry: Fixture.geometry())
        Self.run(&calibration)
        #expect(calibration.phase == .awaitingEyeOnlyCheck)
        #expect(calibration.trainingSampleCounts.count == 9)
        #expect(calibration.trainingSampleCounts.allSatisfy { $0 >= CalibrationRunPolicy.minimumTrainingSamplesPerTarget })
        #expect(calibration.windowResults.count == 10)
        #expect(calibration.report == nil)
        calibration.recordEyeOnlyResponse(.observedPass)
        let report = try #require(calibration.report)
        #expect(report.passesNumericalGate)
        #expect(report.passesProtocolGate)
        #expect(calibration.isComplete)
        #expect(report.novelWindows.allSatisfy { $0.validPredictions == HeldOutPolicy.slots })
        #expect(report.centerControls.count == 2)
    }

    // Break caught: reporting success when the operator did not observe eye-only response.
    @Test func failedEyeOnlyCheckIsNotComplete() {
        var calibration = CalibrationRun(geometry: Fixture.geometry())
        Self.run(&calibration)
        calibration.recordEyeOnlyResponse(.observedFail)
        #expect(calibration.report?.passesNumericalGate == true)
        #expect(!calibration.isComplete)
    }

    // Break caught: retry-until-good or silently fitting without eye data.
    @Test func missingEyesFailsFirstTargetWithCount() {
        var calibration = CalibrationRun(geometry: Fixture.geometry())
        Self.run(&calibration) { _, _ in nil }
        #expect(calibration.phase == .failed(.insufficientTrainingSamples(targetIndex: 0, validSamples: 0)))
        #expect(calibration.calibration == nil)
    }

    // Break caught: extending windows to hide dropped ticks; missing slots must count against coverage.
    @Test func droppedHeldOutTicksFailCoverageInsteadOfExtendingWindows() {
        var calibration = CalibrationRun(geometry: Fixture.geometry())
        Self.run(&calibration, heldOutRate: 10)
        calibration.recordEyeOnlyResponse(.observedPass)
        #expect(calibration.report?.passesNumericalGate == false)
        #expect(!calibration.isComplete)
        #expect(calibration.windowResults.allSatisfy { $0.validPredictions <= 11 })
    }

    // Break caught: keeping an old fit after the viewing setup changes.
    @Test func geometryChangeInvalidatesFit() {
        var calibration = CalibrationRun(geometry: Fixture.geometry())
        Self.run(&calibration)
        calibration.recordEyeOnlyResponse(.observedPass)
        #expect(calibration.isComplete)
        calibration.tick(now: 200, observation: nil, geometry: Fixture.geometry(setup: "moved-phone"))
        #expect(calibration.phase == .failed(.geometryChanged))
        #expect(calibration.calibration == nil)
        #expect(calibration.report == nil)
    }

    @Test func setupChangeMidRunFails() {
        var calibration = CalibrationRun(geometry: Fixture.geometry())
        calibration.start(now: 0)
        calibration.invalidateForSetupChange()
        #expect(calibration.phase == .failed(.geometryChanged))
    }

    @Test func redoClearsFitAndRestartsAtFirstTarget() {
        var calibration = CalibrationRun(geometry: Fixture.geometry())
        Self.run(&calibration)
        calibration.redo(now: 300)
        #expect(calibration.calibration == nil)
        #expect(calibration.windowResults.isEmpty)
        guard case let .training(index, total, target, stage, _) = calibration.phase else {
            Issue.record("expected training phase"); return
        }
        #expect(index == 0 && total == 9 && stage == .settling)
        #expect(target == ScreenPoint(x: 45, y: 60))
    }

    @Test func heldOutOrderInterleavesCenterControlInsideEachPass() {
        for pass in CalibrationRunPolicy.heldOutOrder {
            let center = pass.firstIndex(of: .centerControl)!
            #expect(center > 0 && center < pass.count - 1)
            #expect(Set(pass.filter { $0 != .centerControl }) == Set(HeldOutTarget.novelTargets))
        }
    }
}
