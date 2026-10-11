import Foundation

public enum AirTraceDefaults {
    // Provisional engineering starting values; tune with real-device gesture/fixation evidence.
    public static let maximumSampleAgeSeconds = 0.250
    public static let minimumHandConfidence = 0.5
    public static let pinchCloseDiagonalFraction = 0.035
    public static let pinchReleaseDiagonalFraction = 0.055
    public static let fixationRadiusDiagonalFraction = 0.10
    public static let closureRadiusDiagonalFraction = 0.03
    public static let minimumDistinctSamples = 20
}
/// Both tips are already mapped to canonical full-viewport view points by the capture adapter.
public struct AirTraceHandSample: Sendable {
    public let indexTip: ScreenPoint
    public let thumbTip: ScreenPoint
    public let indexConfidence: Double
    public let thumbConfidence: Double
    public let captureTimestamp: Double
    public let generation: UInt64
    public init(indexTip: ScreenPoint, thumbTip: ScreenPoint, indexConfidence: Double, thumbConfidence: Double, captureTimestamp: Double, generation: UInt64) {
        self.indexTip = indexTip; self.thumbTip = thumbTip
        self.indexConfidence = indexConfidence; self.thumbConfidence = thumbConfidence
        self.captureTimestamp = captureTimestamp; self.generation = generation
    }
}
public struct AirTraceGazeSample: Sendable {
    public let point: ScreenPoint?
    /// True only after the adapter checks calibrated gaze, tracking and open-eye quality.
    public let qualityValid: Bool
    public let captureTimestamp: Double
    public let generation: UInt64
    public init(point: ScreenPoint?, qualityValid: Bool, captureTimestamp: Double, generation: UInt64) {
        self.point = point; self.qualityValid = qualityValid
        self.captureTimestamp = captureTimestamp; self.generation = generation
    }
}
public enum AirTraceRejection: String, Error, Equatable, Sendable {
    case invalidSetup, missingPair, unpairedCapture, stalePair, invalidTimestamp
    case invalidHand, invalidGaze, fixationDrift, duplicateCapture, generationChanged
    case captureGap, interrupted, geometryChanged, insufficientSamples, degenerateStroke
    case openStroke, notReadyForReview, invalidModeTransition
}
public enum AirTraceState: Equatable, Sendable {
    case ready, tracing, candidateReady, accepted
    case invalid(AirTraceRejection)
}
public struct DisplayEllipse: Equatable, Sendable {
    public let center: ScreenPoint
    public let radii: ScreenPoint
}
public struct RegionCandidate: Sendable {
    public let normalizedOffset: ScreenPoint
    public let normalizedRadii: ScreenPoint
    public let geometry: RenderGeometry
    public let normalizedFixation: ScreenPoint
    public let eyeStateDescription: String
    public let captureGeneration: UInt64
}
public struct ReviewedRegion: Sendable {
    public let normalizedOffset: ScreenPoint
    public let normalizedRadii: ScreenPoint
    public let provenance: RegionCandidate
    public let displayGeometry: RenderGeometry

    public func displayEllipse(gaze: ScreenPoint, geometry: RenderGeometry) throws -> DisplayEllipse {
        guard geometry == displayGeometry else { throw AirTraceRejection.geometryChanged }
        guard geometry.contains(gaze) else { throw AirTraceRejection.invalidGaze }
        return DisplayEllipse(
            center: ScreenPoint(x: gaze.x + normalizedOffset.x * geometry.width,
                                y: gaze.y + normalizedOffset.y * geometry.height),
            radii: ScreenPoint(x: normalizedRadii.x * geometry.width,
                               y: normalizedRadii.y * geometry.height))
    }

    /// Retaining a display region across the deliberate front→rear switch does not validate live gaze.
    public func retainedForModeTransition(to geometry: RenderGeometry) throws -> ReviewedRegion {
        guard displayGeometry.mode == .frontSetup, geometry.mode == .rearLive,
              samePhysicalDisplay(displayGeometry, geometry) else {
            throw AirTraceRejection.invalidModeTransition
        }
        return ReviewedRegion(normalizedOffset: normalizedOffset, normalizedRadii: normalizedRadii,
                              provenance: provenance, displayGeometry: geometry)
    }

    private func samePhysicalDisplay(_ a: RenderGeometry, _ b: RenderGeometry) -> Bool {
        a.width == b.width && a.height == b.height && a.scale == b.scale
            && a.orientation == b.orientation && a.viewingSetupID == b.viewingSetupID
    }
}

public struct AirTraceSession: Sendable {
    public private(set) var state: AirTraceState = .ready
    public private(set) var rawTrace: [ScreenPoint] = []
    public private(set) var candidate: RegionCandidate?
    public private(set) var reviewedRegion: ReviewedRegion?
    public let geometry: RenderGeometry
    public let fixation: ScreenPoint
    public let eyeStateDescription: String
    public let captureGeneration: UInt64
    private var lastCaptureTimestamp: Double?
    private var lastSourceGazeTimestamp: Double?

    public init(geometry: RenderGeometry, fixation: ScreenPoint, eyeStateDescription: String, captureGeneration: UInt64) throws {
        guard geometry.mode == .frontSetup, geometry.contains(fixation),
              !eyeStateDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AirTraceRejection.invalidSetup
        }
        self.geometry = geometry
        self.fixation = fixation
        self.eyeStateDescription = eyeStateDescription
        self.captureGeneration = captureGeneration
    }

    /// Validate every source eye event, even when hand inference skips its frame.
    /// Invalid observations cannot be hidden by a later valid hand/gaze pair.
    @discardableResult
    public mutating func observeGaze(_ gaze: AirTraceGazeSample, now: Double,
                                    geometry currentGeometry: RenderGeometry) -> Bool {
        guard currentGeometry == geometry else { invalidate(.geometryChanged); return false }
        expireInputs(now: now, geometry: currentGeometry)
        guard state == .ready || state == .tracing else { return false }
        let reason: AirTraceRejection?
        if !gaze.qualityValid || gaze.point == nil { reason = .invalidGaze }
        else if !now.isFinite || !gaze.captureTimestamp.isFinite || gaze.captureTimestamp < 0
                    || now < gaze.captureTimestamp { reason = .invalidTimestamp }
        else if gaze.generation != captureGeneration { reason = .generationChanged }
        else if now - gaze.captureTimestamp > AirTraceDefaults.maximumSampleAgeSeconds { reason = .stalePair }
        else { reason = gazeRejection(gaze) }
        if let reason {
            if state == .tracing { invalidate(reason) }
            return false
        }
        lastSourceGazeTimestamp = max(lastSourceGazeTimestamp ?? gaze.captureTimestamp, gaze.captureTimestamp)
        return true
    }

    /// Use a periodic watchdog as well as event callbacks: neither stream may silently stop mid-stroke.
    /// Capture timestamps, not callback receipt times, bound source and hand age independently.
    public mutating func expireInputs(now: Double, geometry currentGeometry: RenderGeometry) {
        guard currentGeometry == geometry else { invalidate(.geometryChanged); return }
        guard state == .tracing else { return }
        guard now.isFinite, let handTime = lastCaptureTimestamp, let sourceTime = lastSourceGazeTimestamp,
              now >= handTime, now >= sourceTime else { invalidate(.invalidTimestamp); return }
        guard now - handTime <= AirTraceDefaults.maximumSampleAgeSeconds,
              now - sourceTime <= AirTraceDefaults.maximumSampleAgeSeconds else {
            invalidate(.stalePair)
            return
        }
    }

    /// `now` and both capture timestamps use the same monotonic clock; generation identifies the AR session run.
    public mutating func consume(hand: AirTraceHandSample?, gaze: AirTraceGazeSample?, now: Double,
                                 geometry currentGeometry: RenderGeometry) {
        guard currentGeometry == geometry else { invalidate(.geometryChanged); return }
        guard state == .ready || state == .tracing else { return }
        if let reason = pairRejection(hand: hand, gaze: gaze, now: now) {
            if state == .tracing { invalidate(reason) }
            return
        }
        guard let hand, let gaze else { return } // Pair validation already checked both optional inputs.
        let pinchDistance = hypot(hand.indexTip.x - hand.thumbTip.x, hand.indexTip.y - hand.thumbTip.y)
        if state == .ready {
            guard pinchDistance <= AirTraceDefaults.pinchCloseDiagonalFraction * geometry.diagonal else { return }
            state = .tracing
        }
        rawTrace.append(hand.indexTip)
        lastCaptureTimestamp = hand.captureTimestamp
        lastSourceGazeTimestamp = max(lastSourceGazeTimestamp ?? gaze.captureTimestamp, gaze.captureTimestamp)
        if pinchDistance >= AirTraceDefaults.pinchReleaseDiagonalFraction * geometry.diagonal {
            finishCandidate()
        }
    }

    public mutating func acceptCandidate() throws -> ReviewedRegion {
        guard state == .candidateReady, let candidate else { throw AirTraceRejection.notReadyForReview }
        let region = ReviewedRegion(normalizedOffset: candidate.normalizedOffset,
                                    normalizedRadii: candidate.normalizedRadii,
                                    provenance: candidate, displayGeometry: geometry)
        reviewedRegion = region
        state = .accepted
        return region
    }

    /// Reuse within the same capture generation. Recreate the session after an AR run or setup change.
    public mutating func redo() {
        clearHistory()
        state = .ready
    }

    public mutating func interrupt() { invalidate(.interrupted) }

    private func pairRejection(hand: AirTraceHandSample?, gaze: AirTraceGazeSample?, now: Double) -> AirTraceRejection? {
        guard let hand, let gaze else { return .missingPair }
        guard now.isFinite, hand.captureTimestamp.isFinite, gaze.captureTimestamp.isFinite,
              hand.captureTimestamp >= 0, gaze.captureTimestamp >= 0,
              now >= hand.captureTimestamp, now >= gaze.captureTimestamp else { return .invalidTimestamp }
        guard hand.captureTimestamp == gaze.captureTimestamp, hand.generation == gaze.generation else { return .unpairedCapture }
        guard now - hand.captureTimestamp <= AirTraceDefaults.maximumSampleAgeSeconds else { return .stalePair }
        guard captureGeneration == hand.generation else { return .generationChanged }
        if let lastCaptureTimestamp {
            guard hand.captureTimestamp > lastCaptureTimestamp else { return .duplicateCapture }
            guard hand.captureTimestamp - lastCaptureTimestamp <= AirTraceDefaults.maximumSampleAgeSeconds else { return .captureGap }
        }
        guard validHand(hand) else { return .invalidHand }
        return gazeRejection(gaze)
    }

    private func gazeRejection(_ gaze: AirTraceGazeSample) -> AirTraceRejection? {
        guard gaze.qualityValid, let point = gaze.point, geometry.contains(point) else { return .invalidGaze }
        guard hypot(point.x - fixation.x, point.y - fixation.y)
                <= AirTraceDefaults.fixationRadiusDiagonalFraction * geometry.diagonal else { return .fixationDrift }
        return nil
    }

    private func validHand(_ hand: AirTraceHandSample) -> Bool {
        geometry.contains(hand.indexTip) && geometry.contains(hand.thumbTip)
            && hand.indexConfidence.isFinite && hand.thumbConfidence.isFinite
            && hand.indexConfidence >= AirTraceDefaults.minimumHandConfidence && hand.indexConfidence <= 1
            && hand.thumbConfidence >= AirTraceDefaults.minimumHandConfidence && hand.thumbConfidence <= 1
    }

    private mutating func finishCandidate() {
        var distinct: [ScreenPoint] = []
        for point in rawTrace where !distinct.contains(point) { distinct.append(point) }
        guard distinct.count >= AirTraceDefaults.minimumDistinctSamples else { invalidate(.insufficientSamples); return }
        let xs = rawTrace.map(\.x)
        let ys = rawTrace.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else { invalidate(.degenerateStroke); return }
        guard let first = rawTrace.first, let last = rawTrace.last,
              hypot(last.x - first.x, last.y - first.y)
                <= AirTraceDefaults.closureRadiusDiagonalFraction * geometry.diagonal else { invalidate(.openStroke); return }
        let center = ScreenPoint(x: minX + (maxX - minX) / 2, y: minY + (maxY - minY) / 2)
        candidate = RegionCandidate(
            normalizedOffset: ScreenPoint(x: (center.x - fixation.x) / geometry.width,
                                          y: (center.y - fixation.y) / geometry.height),
            normalizedRadii: ScreenPoint(x: (maxX - minX) / geometry.width / 2,
                                         y: (maxY - minY) / geometry.height / 2),
            geometry: geometry, normalizedFixation: geometry.normalized(fixation),
            eyeStateDescription: eyeStateDescription, captureGeneration: captureGeneration)
        state = .candidateReady
    }

    private mutating func invalidate(_ reason: AirTraceRejection) {
        clearHistory()
        state = .invalid(reason)
    }

    private mutating func clearHistory() {
        rawTrace.removeAll()
        candidate = nil
        reviewedRegion = nil
        lastCaptureTimestamp = nil
        lastSourceGazeTimestamp = nil
    }
}
