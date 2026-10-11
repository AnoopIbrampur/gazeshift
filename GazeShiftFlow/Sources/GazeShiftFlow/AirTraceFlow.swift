import Foundation
import GazeShiftCore

/// Identifies one ARFrame: the AR run generation plus ARKit's own frame timestamp.
/// Hand and eye results are paired by this key, never by "whatever gaze is current".
public struct CaptureFrameKey: Hashable, Sendable {
    public let generation: UInt64
    public let frameTimestamp: Double
    public init(generation: UInt64, frameTimestamp: Double) {
        self.generation = generation; self.frameTimestamp = frameTimestamp
    }
}

/// Vision index/thumb tips for one frame, already in canonical normalized display coordinates
/// (0...1, top-left origin) — exactly what the P1 `HandObservation` carries.
/// `captureTime` is that frame's host-monotonic capture estimate (`FrameIdentity.estimatedCaptureAt`).
public struct NormalizedHandInput: Sendable {
    public let frame: CaptureFrameKey
    public let captureTime: Double
    public let indexTip: ScreenPoint
    public let thumbTip: ScreenPoint
    public let indexConfidence: Double
    public let thumbConfidence: Double
    public init(frame: CaptureFrameKey, captureTime: Double, indexTip: ScreenPoint, thumbTip: ScreenPoint,
                indexConfidence: Double, thumbConfidence: Double) {
        self.frame = frame; self.captureTime = captureTime
        self.indexTip = indexTip; self.thumbTip = thumbTip
        self.indexConfidence = indexConfidence; self.thumbConfidence = thumbConfidence
    }
}

/// Active index-only input, paired to its real source frame before any point is recorded.
public struct NormalizedIndexInput: Sendable {
    public let frame: CaptureFrameKey
    public let captureTime: Double
    public let indexTip: ScreenPoint
    public let indexConfidence: Double
    public init(frame: CaptureFrameKey, captureTime: Double, indexTip: ScreenPoint, indexConfidence: Double) {
        self.frame = frame; self.captureTime = captureTime
        self.indexTip = indexTip; self.indexConfidence = indexConfidence
    }
}

/// Bounded per-frame store of calibrated gaze so a later Vision completion can find the gaze
/// from its own frame. Vision finishes after the eyes for the same ARFrame are known.
public struct AirTracePairer: Sendable {
    /// Enough frames to cover the 250 ms pair-age limit at 60 fps with slack.
    public static let retainedFrames = 32
    private var gazeByFrame: [CaptureFrameKey: AirTraceGazeSample] = [:]
    private var arrival: [CaptureFrameKey] = []

    public init() {}

    public var retainedCount: Int { gazeByFrame.count }

    /// `observation.timestamp` must be the same host-monotonic capture time used for the hand.
    /// Quality uses the reviewed core gate; there is no invented gaze confidence.
    @discardableResult
    /// `unvalidatedFixation`: team-approved demo override. Eyes must still be fresh, tracked, open and have
    /// features (core quality gate), but their calibrated POSITION is not checked; the sample is placed at
    /// this fixation. Never use it for evidence.
    public mutating func recordGaze(frame: CaptureFrameKey, observation: GazeObservation?, calibration: GazeCalibration?,
                                    geometry: RenderGeometry, now: Double,
                                    unvalidatedFixation: ScreenPoint? = nil) -> AirTraceGazeSample {
        let point: ScreenPoint?
        if let unvalidatedFixation {
            point = observation.flatMap { obs in
                GazeQuality.rejectionReason(observation: obs, now: now) == nil ? unvalidatedFixation : nil
            }
        } else {
            point = observation.flatMap { calibration?.livePrediction(observation: $0, now: now, geometry: geometry) }
        }
        let sample = AirTraceGazeSample(point: point, qualityValid: point != nil,
                                        captureTimestamp: observation?.timestamp ?? -1,
                                        generation: frame.generation)
        if gazeByFrame.updateValue(sample, forKey: frame) == nil { arrival.append(frame) }
        while arrival.count > Self.retainedFrames {
            gazeByFrame[arrival.removeFirst()] = nil
        }
        return sample
    }

    /// Returns the gaze recorded for `frame` (consuming it) and converts the hand to view points.
    public mutating func pair(hand: NormalizedHandInput?, frame: CaptureFrameKey,
                              geometry: RenderGeometry) -> (hand: AirTraceHandSample?, gaze: AirTraceGazeSample?) {
        let gaze = gazeByFrame.removeValue(forKey: frame)
        if gaze != nil { arrival.removeAll { $0 == frame } }
        let handSample = hand.flatMap { input -> AirTraceHandSample? in
            guard input.frame == frame else { return nil }
            return AirTraceHandSample(indexTip: Self.viewPoint(input.indexTip, geometry),
                               thumbTip: Self.viewPoint(input.thumbTip, geometry),
                               indexConfidence: input.indexConfidence, thumbConfidence: input.thumbConfidence,
                               captureTimestamp: input.captureTime, generation: input.frame.generation)
        }
        return (handSample, gaze)
    }

    public mutating func reset() {
        gazeByFrame.removeAll()
        arrival.removeAll()
    }

    static func viewPoint(_ normalized: ScreenPoint, _ geometry: RenderGeometry) -> ScreenPoint {
        ScreenPoint(x: normalized.x * geometry.width, y: normalized.y * geometry.height)
    }
}

/// One fixation-checked air-trace attempt: sensing adapter in, reviewed `AirTraceSession` out.
/// Every rule about validity (pinch, staleness, fixation, closure, 20 points) stays in the core session.
public struct AirTraceFlow: Sendable {
    public private(set) var session: AirTraceSession
    private var pairer = AirTracePairer()
    private var sourceByFrame: [CaptureFrameKey: Double] = [:]
    private var sourceArrival: [CaptureFrameKey] = []

    public init(session: AirTraceSession) { self.session = session }

    public var state: AirTraceState { session.state }
    public var rawTrace: [ScreenPoint] { session.rawTrace }
    public var candidate: RegionCandidate? { session.candidate }
    public var geometry: RenderGeometry { session.geometry }

    /// Hand-only input keeps real camera identity/age without manufacturing an eye observation.
    public mutating func recordSource(frame: CaptureFrameKey, captureTime: Double, now: Double,
                                      geometry: RenderGeometry) {
        session.observeSource(captureTimestamp: captureTime, generation: frame.generation, now: now, geometry: geometry)
        guard state == .ready || state == .armed || state == .tracing,
              frame.generation == session.captureGeneration else { return }
        if sourceByFrame.updateValue(captureTime, forKey: frame) == nil { sourceArrival.append(frame) }
        while sourceArrival.count > AirTracePairer.retainedFrames { sourceByFrame[sourceArrival.removeFirst()] = nil }
    }

    public mutating func startDrawing(at now: Double, geometry: RenderGeometry) {
        guard state == .ready else { return }
        resetInputs()
        session.startDrawing(at: now, geometry: geometry)
    }

    public mutating func indexResult(_ index: NormalizedIndexInput?, frame: CaptureFrameKey,
                                     captureTime: Double, now: Double, geometry: RenderGeometry) {
        let sourceTime = sourceByFrame.removeValue(forKey: frame)
        sourceArrival.removeAll { $0 == frame }
        let sample = index.flatMap { input -> AirTraceIndexSample? in
            guard input.frame == frame, input.captureTime == sourceTime,
                  input.captureTime == captureTime else { return nil }
            return AirTraceIndexSample(indexTip: AirTracePairer.viewPoint(input.indexTip, geometry),
                indexConfidence: input.indexConfidence, captureTimestamp: input.captureTime,
                generation: frame.generation)
        }
        session.consumeIndex(sample, captureTimestamp: captureTime, now: now, geometry: geometry)
    }

    public mutating func finishDrawing(now: Double, geometry: RenderGeometry) {
        session.finishDrawing(now: now, geometry: geometry)
        if state != .tracing && state != .armed { resetInputs() }
    }

    public mutating func touchPoint(_ point: ScreenPoint, now: Double, geometry: RenderGeometry) {
        session.consumeTouch(point, now: now, geometry: geometry)
        if case .invalid = state { resetInputs() }
    }

    public mutating func handOnlyResult(_ hand: NormalizedHandInput?, frame: CaptureFrameKey,
                                        now: Double, geometry: RenderGeometry) {
        expireInputs(now: now, geometry: geometry)
        let sourceTime = sourceByFrame.removeValue(forKey: frame)
        sourceArrival.removeAll { $0 == frame }
        let sample = hand.flatMap { input -> AirTraceHandSample? in
            guard input.frame == frame, input.captureTime == sourceTime else { return nil }
            return AirTraceHandSample(indexTip: AirTracePairer.viewPoint(input.indexTip, geometry),
                                      thumbTip: AirTracePairer.viewPoint(input.thumbTip, geometry),
                                      indexConfidence: input.indexConfidence, thumbConfidence: input.thumbConfidence,
                                      captureTimestamp: input.captureTime, generation: frame.generation)
        }
        session.consumeHand(sample, now: now, geometry: geometry)
    }

    /// Call once per ARFrame with that frame's eye observation (nil when ARKit reported no face).
    /// `ignoreGazePosition` is the opt-in Unvalidated gaze demo: eye quality is still enforced, position is not.
    public mutating func recordGaze(frame: CaptureFrameKey, observation: GazeObservation?,
                                    calibration: GazeCalibration?, now: Double, ignoreGazePosition: Bool = false) {
        guard frame.generation == session.captureGeneration else { return }
        let gaze = pairer.recordGaze(frame: frame, observation: observation, calibration: calibration,
                                    geometry: session.geometry, now: now,
                                    unvalidatedFixation: ignoreGazePosition ? session.fixation : nil)
        if !session.observeGaze(gaze, now: now, geometry: session.geometry) { pairer.reset() }
    }

    /// Call when the Vision request for `frame` finishes. `hand` is nil when no confident hand was found;
    /// during a stroke that clears the whole stroke (missing pair), as required.
    public mutating func handResult(_ hand: NormalizedHandInput?, frame: CaptureFrameKey,
                                    now: Double, geometry: RenderGeometry) {
        expireInputs(now: now, geometry: geometry)
        guard session.state == .ready || session.state == .tracing else { return }
        let pair = pairer.pair(hand: hand, frame: frame, geometry: session.geometry)
        session.consume(hand: pair.hand, gaze: pair.gaze, now: now, geometry: geometry)
    }

    /// Called by the host watchdog even when neither source nor Vision delivers another event.
    public mutating func expireInputs(now: Double, geometry: RenderGeometry) {
        session.expireInputs(now: now, geometry: geometry)
        if case .invalid = session.state { resetInputs() }
    }

    /// Min/max bounding ellipse of the pending candidate, for the review screen (ANO-8).
    public var candidateEllipse: ReviewEllipse? {
        guard let candidate else { return nil }
        let geometry = session.geometry
        return ReviewEllipse(
            center: ScreenPoint(x: session.fixation.x + candidate.normalizedOffset.x * geometry.width,
                                y: session.fixation.y + candidate.normalizedOffset.y * geometry.height),
            radii: ScreenPoint(x: candidate.normalizedRadii.x * geometry.width,
                               y: candidate.normalizedRadii.y * geometry.height))
    }

    public mutating func accept() throws -> ReviewedRegion { try session.acceptCandidate() }

    public mutating func redo() {
        resetInputs()
        session.redo()
    }

    /// Mode switch, pause, layout change or AR re-run: the stroke cannot continue.
    public mutating func interrupt() {
        resetInputs()
        session.interrupt()
    }

    private mutating func resetInputs() {
        pairer.reset()
        sourceByFrame.removeAll()
        sourceArrival.removeAll()
    }
}

/// Review-time ellipse in view points around the stationary fixation (not around gaze).
public struct ReviewEllipse: Equatable, Sendable {
    public let center: ScreenPoint
    public let radii: ScreenPoint
}
