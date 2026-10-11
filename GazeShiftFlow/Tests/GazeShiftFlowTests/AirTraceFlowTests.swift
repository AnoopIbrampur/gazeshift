import Testing
import GazeShiftCore
@testable import GazeShiftFlow

@Suite("Air-trace pairing (fixtures)")
struct AirTraceFlowTests {
    // Break caught: pairing by host time or recentering the region onto gaze instead of fixation.
    @Test func closedPinchStrokeBecomesReviewableCandidateAroundFixation() throws {
        var flow = Fixture.tracedFlow()
        #expect(flow.state == .candidateReady)
        #expect(flow.rawTrace.count == 25)
        let ellipse = try #require(flow.candidateEllipse)
        #expect(abs(ellipse.center.x - 120) < 1e-9)
        #expect(abs(ellipse.center.y - 140) < 1e-9)
        #expect(abs(ellipse.radii.x - 30) < 1e-9)
        #expect(abs(ellipse.radii.y - 20) < 1e-9)
        _ = try flow.accept()
        #expect(flow.state == .accepted)
    }

    // Break caught: a hand result consuming "current" gaze when its own frame had none.
    @Test func handWithoutSameFrameGazeClearsWholeStroke() {
        var flow = Fixture.makeFlow()
        for i in 0..<5 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i)) }
        #expect(flow.state == .tracing)
        Fixture.step(&flow, frame: 5, point: Fixture.outlinePoint(5), recordGaze: false)
        #expect(flow.state == .invalid(.missingPair))
        #expect(flow.rawTrace.isEmpty)
    }

    // Break caught: blinks treated as valid gaze because a stale prediction lingers.
    @Test func blinkDuringStrokeInvalidatesGaze() {
        var flow = Fixture.makeFlow()
        for i in 0..<5 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i)) }
        let time = 1 + 5 * 0.02
        Fixture.step(&flow, frame: 5, point: Fixture.outlinePoint(5),
                     gaze: Fixture.observation(at: time, looking: Fixture.fixation, blink: 0.9))
        #expect(flow.state == .invalid(.invalidGaze))
    }

    // Break caught: eyes following the finger instead of holding the stationary reference.
    @Test func lookingAwayFromFixationIsDrift() {
        var flow = Fixture.makeFlow()
        for i in 0..<5 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i)) }
        let time = 1 + 5 * 0.02
        Fixture.step(&flow, frame: 5, point: Fixture.outlinePoint(5),
                     gaze: Fixture.observation(at: time, looking: ScreenPoint(x: 260, y: 350)))
        #expect(flow.state == .invalid(.fixationDrift))
    }

    // Break caught: Vision skipping a bad-eye frame must not hide that interruption.
    @Test(arguments: SkippedEyeFailure.allCases)
    func unpairedEyeFailureClearsStrokeUntilExplicitRedo(_ failure: SkippedEyeFailure) {
        var flow = Fixture.makeFlow()
        for i in 0..<5 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i)) }
        flow.recordGaze(frame: Fixture.frame(5), observation: failure.observation(at: 1.1),
                        calibration: Fixture.calibration(Fixture.geometry()), now: 1.105)
        #expect(flow.state == .invalid(failure.reason))
        #expect(flow.rawTrace.isEmpty)
        #expect(flow.candidate == nil)

        // No hand completion exists for frame 5. Later valid pairs and release cannot salvage it.
        for i in 6..<24 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i)) }
        Fixture.step(&flow, frame: 24, point: Fixture.outlinePoint(0), pinched: false)
        #expect(flow.state == .invalid(failure.reason))
        #expect(flow.rawTrace.isEmpty)
        #expect(flow.candidate == nil)

        flow.redo()
        for i in 25..<49 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i - 25)) }
        Fixture.step(&flow, frame: 49, point: Fixture.outlinePoint(0), pinched: false)
        #expect(flow.state == .candidateReady)
    }

    // Break caught: a hand carrying another ARFrame key must not consume this frame's gaze.
    @Test func mismatchedHandFrameCannotJoinStroke() {
        var flow = Fixture.makeFlow()
        Fixture.step(&flow, frame: 0, point: Fixture.outlinePoint(0))
        let key = Fixture.frame(1)
        flow.recordGaze(frame: key, observation: Fixture.observation(at: 1.02, looking: Fixture.fixation),
                        calibration: Fixture.calibration(Fixture.geometry()), now: 1.025)
        flow.handResult(Fixture.hand(Fixture.frame(2), time: 1.02, index: Fixture.outlinePoint(1)),
                        frame: key, now: 1.03, geometry: Fixture.geometry())
        #expect(flow.state == .invalid(.missingPair))
        #expect(flow.rawTrace.isEmpty)
    }

    // Break caught: a stalled source leaving an unfinished trace alive without another callback.
    @Test func sourceExpiryClearsStrokeWithoutAnotherCallback() {
        var flow = Fixture.makeFlow()
        Fixture.step(&flow, frame: 0, point: Fixture.outlinePoint(0))
        flow.expireInputs(now: 1.251, geometry: Fixture.geometry())
        #expect(flow.state == .invalid(.stalePair))
        #expect(flow.rawTrace.isEmpty)
        Fixture.step(&flow, frame: 14, point: Fixture.outlinePoint(0), pinched: false)
        #expect(flow.state == .invalid(.stalePair))
        #expect(flow.candidate == nil)
    }

    // Break caught: healthy source frames must not mask an expired hand-inference stream.
    @Test func handExpiryClearsStrokeWhileSourceContinues() {
        var flow = Fixture.makeFlow()
        Fixture.step(&flow, frame: 0, point: Fixture.outlinePoint(0))
        for index in 1...12 {
            let time = 1 + Double(index) * 0.02
            flow.recordGaze(frame: Fixture.frame(index), observation: Fixture.observation(at: time, looking: Fixture.fixation),
                            calibration: Fixture.calibration(Fixture.geometry()), now: time)
        }
        flow.expireInputs(now: 1.251, geometry: Fixture.geometry())
        #expect(flow.state == .invalid(.stalePair))
        #expect(flow.rawTrace.isEmpty)
    }

    // Break caught: a delayed completion arriving before the watchdog tick cannot bridge an expired hand stream.
    @Test func delayedVisionCompletionCannotBridgeHandExpiry() {
        var flow = Fixture.makeFlow()
        Fixture.step(&flow, frame: 0, point: Fixture.outlinePoint(0))
        for index in 1...12 {
            let time = 1 + Double(index) * 0.02
            flow.recordGaze(frame: Fixture.frame(index), observation: Fixture.observation(at: time, looking: Fixture.fixation),
                            calibration: Fixture.calibration(Fixture.geometry()), now: time)
        }
        // This result is still individually younger than 250 ms, but the active stroke has had no
        // hand update for 260 ms. Its original capture time cannot refresh that missing interval.
        flow.handResult(Fixture.hand(Fixture.frame(1), time: 1.02, index: Fixture.outlinePoint(1)),
                        frame: Fixture.frame(1), now: 1.26, geometry: Fixture.geometry())
        #expect(flow.state == .invalid(.stalePair))
        #expect(flow.rawTrace.isEmpty)
    }

    // Break caught: incoming source frames cannot erase an expiry that occurred between callbacks.
    @Test func freshSourceAfterExpiryCannotSaveOrReleaseStroke() {
        var flow = Fixture.makeFlow()
        Fixture.step(&flow, frame: 0, point: Fixture.outlinePoint(0))
        flow.recordGaze(frame: Fixture.frame(14), observation: Fixture.observation(at: 1.28, looking: Fixture.fixation),
                        calibration: Fixture.calibration(Fixture.geometry()), now: 1.28)
        #expect(flow.state == .invalid(.stalePair))
        Fixture.step(&flow, frame: 15, point: Fixture.outlinePoint(0), pinched: false)
        #expect(flow.state == .invalid(.stalePair))
        #expect(flow.candidate == nil)
        flow.redo()
        for index in 16..<40 { Fixture.step(&flow, frame: index, point: Fixture.outlinePoint(index - 16)) }
        Fixture.step(&flow, frame: 40, point: Fixture.outlinePoint(0), pinched: false)
        #expect(flow.state == .candidateReady)
    }

    // Break caught: missing hand during a stroke being silently skipped.
    @Test func noHandDuringStrokeClearsStroke() {
        var flow = Fixture.makeFlow()
        for i in 0..<5 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i)) }
        let key = Fixture.frame(5)
        let time = 1 + 5 * 0.02
        flow.recordGaze(frame: key, observation: Fixture.observation(at: time, looking: Fixture.fixation),
                        calibration: Fixture.calibration(Fixture.geometry()), now: time)
        flow.handResult(nil, frame: key, now: time + 0.01, geometry: Fixture.geometry())
        #expect(flow.state == .invalid(.missingPair))
    }

    // Break caught: a stroke staying "tracing" forever after the hand silently leaves the frame.
    @Test func handSilenceLongerThanPairAgeClearsStroke() {
        var flow = Fixture.makeFlow()
        for i in 0..<5 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i)) }
        let lastHand = 1 + 4 * 0.02
        flow.expireInputs(now: lastHand + 0.2, geometry: Fixture.geometry())
        #expect(flow.state == .tracing)
        flow.expireInputs(now: lastHand + 0.3, geometry: Fixture.geometry())
        if case .invalid = flow.state {} else { Issue.record("expected invalid, got \(flow.state)") }
        #expect(flow.rawTrace.isEmpty)
    }

    @Test func staleHandExpiryIgnoresIdleSession() {
        var flow = Fixture.makeFlow()
        flow.expireInputs(now: 100, geometry: Fixture.geometry())
        #expect(flow.state == .ready)
    }

    @Test func redoAfterInvalidStartsCleanAndCanSucceed() {
        var flow = Fixture.makeFlow()
        Fixture.step(&flow, frame: 0, point: Fixture.outlinePoint(0))
        flow.interrupt()
        #expect(flow.state == .invalid(.interrupted))
        flow.redo()
        #expect(flow.state == .ready)
        for i in 1...24 { Fixture.step(&flow, frame: i, point: Fixture.outlinePoint(i - 1)) }
        Fixture.step(&flow, frame: 25, point: Fixture.outlinePoint(0), pinched: false)
        #expect(flow.state == .candidateReady)
    }

    @Test func pairerIsBoundedAndIgnoresOtherGenerations() {
        var pairer = AirTracePairer()
        let geometry = Fixture.geometry()
        for i in 0..<40 {
            pairer.recordGaze(frame: Fixture.frame(i), observation: nil, calibration: nil, geometry: geometry, now: 1)
        }
        #expect(pairer.retainedCount == AirTracePairer.retainedFrames)
        let oldest = pairer.pair(hand: nil, frame: Fixture.frame(0), geometry: geometry)
        #expect(oldest.gaze == nil)

        var flow = Fixture.makeFlow()
        flow.recordGaze(frame: Fixture.frame(0, generation: 2), observation: Fixture.observation(at: 1, looking: Fixture.fixation),
                        calibration: Fixture.calibration(geometry), now: 1)
        Fixture.step(&flow, frame: 0, point: Fixture.outlinePoint(0), recordGaze: false)
        #expect(flow.state == .ready) // Not started: no same-generation pair.
    }

    @Test func normalizedTipsBecomeViewPoints() {
        var pairer = AirTracePairer()
        let geometry = Fixture.geometry()
        let hand = Fixture.hand(Fixture.frame(0), time: 1, index: ScreenPoint(x: 75, y: 100))
        let paired = pairer.pair(hand: hand, frame: Fixture.frame(0), geometry: geometry)
        #expect(abs(paired.hand!.indexTip.x - 75) < 1e-9)
        #expect(abs(paired.hand!.indexTip.y - 100) < 1e-9)
    }
}

enum SkippedEyeFailure: CaseIterable, Sendable {
    case blink, missingFace, fixationDrift

    var reason: AirTraceRejection { self == .fixationDrift ? .fixationDrift : .invalidGaze }

    func observation(at time: Double) -> GazeObservation? {
        switch self {
        case .blink: Fixture.observation(at: time, looking: Fixture.fixation, blink: 0.9)
        case .missingFace: nil
        case .fixationDrift: Fixture.observation(at: time, looking: ScreenPoint(x: 260, y: 350))
        }
    }
}
