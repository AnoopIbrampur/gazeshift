import Testing
import GazeShiftCore
@testable import GazeShiftFlow

@Suite("Hand-only screen-fixed experiment (fixtures)")
struct ScreenFixedTests {
    func makeFlow() throws -> AirTraceFlow {
        AirTraceFlow(session: try AirTraceSession(handOnlyGeometry: Fixture.geometry(), captureGeneration: 1))
    }

    func step(_ flow: inout AirTraceFlow, _ i: Int, point: ScreenPoint? = nil, released: Bool = false) {
        let time = 1 + Double(i) * 0.02
        let frame = Fixture.frame(i)
        flow.recordSource(frame: frame, captureTime: time, now: time, geometry: Fixture.geometry())
        flow.handOnlyResult(Fixture.hand(frame, time: time, index: point ?? Fixture.outlinePoint(i % 24), pinched: !released),
                            frame: frame, now: time + 0.005, geometry: Fixture.geometry())
    }

    func traced() throws -> AirTraceFlow {
        var flow = try makeFlow()
        for i in 0..<24 { step(&flow, i) }
        step(&flow, 24, released: true)
        return flow
    }

    // Break caught: pairing a hand stroke with missing eyes/calibration instead of real source identity.
    @Test func acceptsClosedHandStrokeWithZeroEyeEvents() throws {
        var flow = try traced()
        #expect(flow.state == .candidateReady)
        let region = try flow.accept()
        let ellipse = try region.screenFixedEllipse(geometry: Fixture.geometry())
        #expect(abs(ellipse.center.x - 120) < 1e-9)
        #expect(abs(ellipse.center.y - 140) < 1e-9)
        #expect(ellipse.radii == ScreenPoint(x: 30, y: 20))
    }

    // Break caught: eye callbacks accidentally moving the fixed region or invalidating its stroke.
    @Test func eyeEventsCannotAffectHandOnlySession() throws {
        var flow = try makeFlow()
        for i in 0..<24 {
            step(&flow, i)
            flow.recordGaze(frame: Fixture.frame(i), observation: nil, calibration: nil, now: 1 + Double(i) * 0.02)
        }
        step(&flow, 24, released: true)
        #expect(flow.state == .candidateReady)
    }

    // Break caught: stale/missing/low-quality or unrelated hand captures get joined into one outline.
    @Test func badHandInputClearsStroke() throws {
        for variant in 0..<7 {
            var flow = try makeFlow()
            step(&flow, 0)
            let frame = Fixture.frame(1, generation: variant == 1 ? 2 : 1)
            let time = variant == 2 ? 0.5 : 1.02
            flow.recordSource(frame: frame, captureTime: time, now: 1.02, geometry: Fixture.geometry())
            let input = NormalizedHandInput(frame: variant == 3 ? Fixture.frame(2) : frame,
                captureTime: time, indexTip: ScreenPoint(x: variant == 4 ? 2 : 0.4, y: 0.35),
                thumbTip: ScreenPoint(x: 0.401, y: 0.35), indexConfidence: variant == 5 ? 0.1 : 0.9,
                thumbConfidence: variant == 6 ? .nan : 0.9)
            flow.handOnlyResult(variant == 0 ? nil : input, frame: frame, now: 1.03, geometry: Fixture.geometry())
            if case .invalid = flow.state {} else { Issue.record("Invalid hand variant \(variant) survived") }
            #expect(flow.rawTrace.isEmpty)
        }
    }

    // Break caught: continued camera callbacks or a late Vision result rescue an expired stroke.
    @Test func sourceAndHandWatchdogsAndGeometryStillClearStroke() throws {
        for variant in 0..<3 {
            var flow = try makeFlow()
            step(&flow, 0)
            if variant == 1 {
                flow.recordSource(frame: Fixture.frame(1), captureTime: 1.2, now: 1.2, geometry: Fixture.geometry())
            }
            flow.expireInputs(now: variant == 2 ? 1.02 : 1.251,
                              geometry: Fixture.geometry(setup: variant == 2 ? "moved" : "fixture-setup"))
            #expect(flow.state == .invalid(variant == 2 ? .geometryChanged : .stalePair))
        }
    }

    // Break caught: manual mode weakening minimum/area/closure rules from the actual hand trace.
    @Test func rejectsShortFlatAndOpenOutlines() throws {
        for variant in 0..<3 {
            var flow = try makeFlow()
            let count = variant == 0 ? 18 : 24
            for i in 0..<count {
                step(&flow, i, point: variant == 1 ? ScreenPoint(x: 80 + Double(i), y: 140) : nil)
            }
            let release = variant == 2 ? ScreenPoint(x: 170, y: 180) :
                (variant == 1 ? ScreenPoint(x: 80, y: 140) : Fixture.outlinePoint(0))
            step(&flow, count, point: release, released: true)
            #expect(flow.state == .invalid(variant == 0 ? .insufficientSamples : (variant == 1 ? .degenerateStroke : .openStroke)))
        }
    }

    // Break caught: fixed placement requiring a fake gaze margin, clamping edges, or allowing overlap.
    @Test func fixedCopyUsesOriginalBoundsWithoutGazeMargin() throws {
        var flow = try traced()
        let region = try flow.accept()
        let bounds = ScreenRect(x: 0, y: 0, width: 300, height: 400)
        let result = PlacementPlanner.planScreenFixed(region: region, geometry: Fixture.geometry(),
            userOffset: ScreenPoint(x: 100, y: 150), cameraSamplingBounds: bounds)
        guard case let .accepted(placement) = result else { Issue.record("Valid fixed placement rejected"); return }
        #expect(placement.source == ScreenRect(x: 90, y: 120, width: 60, height: 40))
        #expect(placement.destination == ScreenRect(x: 190, y: 270, width: 60, height: 40))
        #expect(placement.samplingSource == .originalFrame)
        #expect(placement.safetyGapPoints == 0)
        #expect(PlacementPlanner.planScreenFixed(region: region, geometry: Fixture.geometry(),
            userOffset: ScreenPoint(x: 60, y: 0), cameraSamplingBounds: bounds) == .rejected(.destinationOverlapsRegion))
        #expect(PlacementPlanner.planScreenFixed(region: region, geometry: Fixture.geometry(),
            userOffset: ScreenPoint(x: 300, y: 0), cameraSamplingBounds: bounds) == .rejected(.destinationOutsideBounds))
    }

    // Break caught: simulation modes differ in mask geometry or retain layers over a failed camera.
    @Test func comparisonsUseIdenticalFixedRegionAndClearOnSourceLoss() throws {
        var flow = try traced()
        let front = try flow.accept()
        let region = try front.retainedForModeTransition(to: Fixture.geometry(.rearLive))
        func plan(_ mode: ViewMode, healthy: Bool = true) -> CompositionPlan {
            CompositionPlanner.planScreenFixed(mode: mode, region: region, sourceAvailable: healthy,
                geometry: Fixture.geometry(.rearLive), userOffset: ScreenPoint(x: 100, y: 150),
                cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: 300, height: 400))
        }
        #expect(plan(.comparison(.original)).isOriginalOnly)
        #expect(plan(.live).blur == nil)
        #expect(plan(.comparison(.simulatedBlur)).copy == nil)
        #expect(plan(.comparison(.simulatedBlur)).blur == plan(.comparison(.simulatedBlurPlusCopy)).blur)
        for mode in [ViewMode.live, .comparison(.original), .comparison(.simulatedBlur), .comparison(.simulatedBlurPlusCopy)] {
            #expect(plan(mode, healthy: false).isOriginalOnly)
            #expect(plan(mode, healthy: false).statusText == "Scene unavailable")
        }
        #expect(throws: AirTraceRejection.geometryChanged) { try front.screenFixedEllipse(geometry: Fixture.geometry(.rearLive)) }
        #expect(throws: AirTraceRejection.invalidModeTransition) { try front.retainedForModeTransition(to: Fixture.geometry(.rearLive, setup: "moved")) }
    }
}
