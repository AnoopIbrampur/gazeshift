import Foundation
import GazeShiftCore
@testable import GazeShiftFlow

// FIXTURES ONLY: synthetic eye features and hand tips. Passing these tests proves flow logic,
// not device calibration, real air tracing or live-eye behavior.
enum Fixture {
    static let fixation = ScreenPoint(x: 160, y: 210)

    static func geometry(_ mode: TrackingMode = .frontSetup, setup: String = "fixture-setup") -> RenderGeometry {
        try! RenderGeometry(width: 300, height: 400, scale: 3, orientation: .portrait, mode: mode, viewingSetupID: setup)
    }

    /// Linear fixture eye model: view point = (150, 200) + 1000 × features.
    static func features(looking point: ScreenPoint) -> EyeFeatures {
        try! EyeFeatures(horizontal: (point.x - 150) / 1000, vertical: (point.y - 200) / 1000)
    }

    static func observation(at time: Double, looking point: ScreenPoint, blink: Double = 0.1) -> GazeObservation {
        GazeObservation(timestamp: time, isTracked: true, leftBlink: blink, rightBlink: blink,
                        features: features(looking: point))
    }

    static func calibration(_ geometry: RenderGeometry) -> GazeCalibration {
        let samples = CalibrationRunPolicy.trainingTargets.map { normalized in
            let target = ScreenPoint(x: normalized.x * geometry.width, y: normalized.y * geometry.height)
            return CalibrationSample(features: features(looking: target), target: target)
        }
        return try! GazeCalibration.fit(samples: samples, geometry: geometry)
    }

    static func frame(_ index: Int, generation: UInt64 = 1) -> CaptureFrameKey {
        // ARKit's frame clock deliberately differs from the host clock.
        CaptureFrameKey(generation: generation, frameTimestamp: 5000 + Double(index) * 0.02)
    }

    static func hand(_ frame: CaptureFrameKey, time: Double, index point: ScreenPoint,
                     pinched: Bool = true, geometry: RenderGeometry = geometry()) -> NormalizedHandInput {
        let thumbOffset = pinched ? 1.0 : 60.0
        return NormalizedHandInput(frame: frame, captureTime: time,
                                   indexTip: ScreenPoint(x: point.x / geometry.width, y: point.y / geometry.height),
                                   thumbTip: ScreenPoint(x: (point.x + thumbOffset) / geometry.width, y: point.y / geometry.height),
                                   indexConfidence: 0.9, thumbConfidence: 0.9)
    }

    /// 24-point closed outline: min/max bounds give center (120, 140) and radii (30, 20).
    static func outlinePoint(_ i: Int) -> ScreenPoint {
        let angle = 2 * Double.pi * Double(i) / 24
        return ScreenPoint(x: 120 + 30 * cos(angle), y: 140 + 20 * sin(angle))
    }

    static func makeFlow() -> AirTraceFlow {
        let session = try! AirTraceSession(geometry: geometry(), fixation: fixation,
                                           eyeStateDescription: "fixture: both eyes open", captureGeneration: 1)
        return AirTraceFlow(session: session)
    }

    /// Runs one paired frame through the flow.
    static func step(_ flow: inout AirTraceFlow, frame index: Int, point: ScreenPoint, pinched: Bool = true,
                     gaze: GazeObservation? = nil, recordGaze: Bool = true) {
        let time = 1 + Double(index) * 0.02
        let key = frame(index)
        let calibration = calibration(geometry())
        if recordGaze {
            flow.recordGaze(frame: key, observation: gaze ?? observation(at: time, looking: fixation),
                            calibration: calibration, now: time + 0.005)
        }
        flow.handResult(hand(key, time: time, index: point, pinched: pinched), frame: key,
                        now: time + 0.01, geometry: geometry())
    }

    static func tracedFlow() -> AirTraceFlow {
        var flow = makeFlow()
        for i in 0..<24 { step(&flow, frame: i, point: outlinePoint(i)) }
        step(&flow, frame: 24, point: outlinePoint(0), pinched: false)
        return flow
    }

    /// An accepted region retained into rear live mode on the same physical display.
    static func rearRegion() -> ReviewedRegion {
        var flow = tracedFlow()
        let region = try! flow.accept()
        return try! region.retainedForModeTransition(to: geometry(.rearLive))
    }
}
