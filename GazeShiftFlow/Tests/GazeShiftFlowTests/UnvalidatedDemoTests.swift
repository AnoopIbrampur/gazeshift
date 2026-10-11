import Testing
import GazeShiftCore
@testable import GazeShiftFlow

@Suite("Unvalidated gaze demo override (fixtures)")
struct UnvalidatedDemoTests {
    static let farGaze = ScreenPoint(x: 260, y: 350) // well beyond the 0.10-diagonal fixation radius

    static func step(_ flow: inout AirTraceFlow, _ i: Int, point: ScreenPoint, pinched: Bool = true,
                     blink: Double = 0.1, override: Bool) {
        let time = 1 + Double(i) * 0.02
        let key = Fixture.frame(i)
        flow.recordGaze(frame: key, observation: Fixture.observation(at: time, looking: farGaze, blink: blink),
                        calibration: Fixture.calibration(Fixture.geometry()), now: time + 0.005,
                        ignoreGazePosition: override)
        flow.handResult(Fixture.hand(key, time: time, index: point, pinched: pinched), frame: key,
                        now: time + 0.01, geometry: Fixture.geometry())
    }

    // Break caught: inaccurate (but open, tracked) eyes making every demo stroke fail as drift.
    @Test func overrideCompletesStrokeDespiteInaccurateGazePosition() {
        var strict = Fixture.makeFlow()
        for i in 0..<3 { Self.step(&strict, i, point: Fixture.outlinePoint(i), override: false) }
        #expect(strict.state != .tracing)

        var demo = Fixture.makeFlow()
        for i in 0..<24 { Self.step(&demo, i, point: Fixture.outlinePoint(i), override: true) }
        Self.step(&demo, 24, point: Fixture.outlinePoint(0), pinched: false, override: true)
        #expect(demo.state == .candidateReady)
    }

    // Break caught: the override silently accepting closed eyes.
    @Test func overrideStillClearsStrokeOnBlink() {
        var demo = Fixture.makeFlow()
        for i in 0..<5 { Self.step(&demo, i, point: Fixture.outlinePoint(i), override: true) }
        #expect(demo.state == .tracing)
        Self.step(&demo, 5, point: Fixture.outlinePoint(5), blink: 0.9, override: true)
        if case .invalid = demo.state {} else { Issue.record("expected invalid, got \(demo.state)") }
        #expect(demo.rawTrace.isEmpty)
    }
}
