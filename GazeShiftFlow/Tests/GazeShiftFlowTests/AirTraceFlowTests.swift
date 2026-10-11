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
        flow.expireStaleHand(now: lastHand + 0.2)
        #expect(flow.state == .tracing)
        flow.expireStaleHand(now: lastHand + 0.3)
        #expect(flow.state == .invalid(.missingPair))
        #expect(flow.rawTrace.isEmpty)
    }

    @Test func staleHandExpiryIgnoresIdleSession() {
        var flow = Fixture.makeFlow()
        flow.expireStaleHand(now: 100)
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
