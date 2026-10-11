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
    // Numerical degeneracy guard relative to the outline's bounds, not a measured vision threshold.
    public static let minimumTouchAreaBoundingFraction = 1e-6
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
/// The active manual drawing path needs only a real, mapped index fingertip.
public struct AirTraceIndexSample: Sendable {
    public let indexTip: ScreenPoint
    public let indexConfidence: Double
    public let captureTimestamp: Double
    public let generation: UInt64
    public init(indexTip: ScreenPoint, indexConfidence: Double, captureTimestamp: Double, generation: UInt64) {
        self.indexTip = indexTip; self.indexConfidence = indexConfidence
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
    case invalidHand, invalidTouch, invalidGaze, fixationDrift, duplicateCapture, generationChanged
    case captureGap, interrupted, geometryChanged, insufficientSamples, degenerateStroke
    case openStroke, notReadyForReview, invalidModeTransition
}
public enum AirTraceState: Equatable, Sendable {
    case ready, armed, tracing, candidateReady, accepted
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

    /// Explicit display-space approximation: eye movement never changes this saved outline.
    public func screenFixedEllipse(geometry: RenderGeometry) throws -> DisplayEllipse {
        guard geometry == displayGeometry else { throw AirTraceRejection.geometryChanged }
        return DisplayEllipse(
            center: ScreenPoint(x: (provenance.normalizedFixation.x + normalizedOffset.x) * geometry.width,
                                y: (provenance.normalizedFixation.y + normalizedOffset.y) * geometry.height),
            radii: ScreenPoint(x: normalizedRadii.x * geometry.width,
                               y: normalizedRadii.y * geometry.height))
    }

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
    private var handOnly = false
    private var indexOnly = false
    private var screenTouch = false
    private var drawingStartedAt: Double?

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

    /// The center is only a coordinate reference for storage; no gaze measurement is fabricated.
    public init(handOnlyGeometry geometry: RenderGeometry, captureGeneration: UInt64) throws {
        try self.init(geometry: geometry, fixation: ScreenPoint(x: geometry.width / 2, y: geometry.height / 2),
                      eyeStateDescription: "Eye tracking disabled · screen-fixed approximation", captureGeneration: captureGeneration)
        handOnly = true
    }

    public init(indexOnlyGeometry geometry: RenderGeometry, captureGeneration: UInt64) throws {
        try self.init(handOnlyGeometry: geometry, captureGeneration: captureGeneration)
        indexOnly = true
    }

    /// Rear-screen touch points are direct UI input; the center is only a storage reference.
    public init(screenTouchGeometry geometry: RenderGeometry, captureGeneration: UInt64) throws {
        guard geometry.mode == .rearLive else { throw AirTraceRejection.invalidSetup }
        self.geometry = geometry
        fixation = ScreenPoint(x: geometry.width / 2, y: geometry.height / 2)
        eyeStateDescription = "Eye tracking disabled · screen-fixed touch approximation"
        self.captureGeneration = captureGeneration
        handOnly = true
        screenTouch = true
    }

    /// Arming records no cached cursor points. Only captures at or after this explicit action qualify.
    public mutating func startDrawing(at now: Double, geometry currentGeometry: RenderGeometry) {
        guard indexOnly || screenTouch, state == .ready else { return }
        guard currentGeometry == geometry else { invalidate(.geometryChanged); return }
        guard now.isFinite, now >= 0 else { invalidate(.invalidTimestamp); return }
        clearHistory()
        drawingStartedAt = now
        state = .armed
    }

    /// `captureTimestamp` also accompanies nil Vision results, so pre-Start completions can be ignored.
    public mutating func consumeIndex(_ index: AirTraceIndexSample?, captureTimestamp: Double,
                                      now: Double, geometry currentGeometry: RenderGeometry) {
        guard indexOnly, state == .armed || state == .tracing else { return }
        if let drawingStartedAt, captureTimestamp.isFinite, captureTimestamp < drawingStartedAt { return }
        expireInputs(now: now, geometry: currentGeometry)
        guard state == .armed || state == .tracing else { return }
        let reason: AirTraceRejection?
        if let index {
            if !now.isFinite || !index.captureTimestamp.isFinite || index.captureTimestamp < 0
                || now < index.captureTimestamp { reason = .invalidTimestamp }
            else if index.captureTimestamp != captureTimestamp { reason = .unpairedCapture }
            else if now - index.captureTimestamp > AirTraceDefaults.maximumSampleAgeSeconds { reason = .stalePair }
            else if index.generation != captureGeneration { reason = .generationChanged }
            else if let lastCaptureTimestamp, index.captureTimestamp <= lastCaptureTimestamp { reason = .duplicateCapture }
            else if let lastCaptureTimestamp, index.captureTimestamp - lastCaptureTimestamp > AirTraceDefaults.maximumSampleAgeSeconds { reason = .captureGap }
            else if !geometry.contains(index.indexTip) || !index.indexConfidence.isFinite
                || index.indexConfidence < AirTraceDefaults.minimumHandConfidence || index.indexConfidence > 1 { reason = .invalidHand }
            else if let sourceTime = lastSourceGazeTimestamp {
                reason = now < sourceTime ? .invalidTimestamp
                    : (now - sourceTime > AirTraceDefaults.maximumSampleAgeSeconds ? .stalePair : nil)
            } else { reason = .missingPair }
        } else { reason = .missingPair }
        if let reason {
            // Wait for the first usable post-Start sample; once drawing, a loss clears the attempt.
            if state == .tracing { invalidate(reason) }
            return
        }
        guard let index else { return }
        rawTrace.append(index.indexTip)
        lastCaptureTimestamp = index.captureTimestamp
        state = .tracing
    }

    public mutating func finishDrawing(now: Double, geometry currentGeometry: RenderGeometry) {
        guard indexOnly || screenTouch, state == .armed || state == .tracing else { return }
        expireInputs(now: now, geometry: currentGeometry)
        guard state == .armed || state == .tracing else { return }
        finishCandidate()
    }

    /// Touch time is the host monotonic UI clock; it is not a camera or hand observation.
    public mutating func consumeTouch(_ point: ScreenPoint, now: Double, geometry currentGeometry: RenderGeometry) {
        guard screenTouch, state == .armed || state == .tracing else { return }
        expireInputs(now: now, geometry: currentGeometry)
        guard state == .armed || state == .tracing else { return }
        guard now.isFinite, now >= 0, let drawingStartedAt, now >= drawingStartedAt else {
            invalidate(.invalidTimestamp); return
        }
        guard geometry.contains(point) else { invalidate(.invalidTouch); return }
        guard let sourceTime = lastSourceGazeTimestamp else { return }
        guard now >= sourceTime else { invalidate(.invalidTimestamp); return }
        guard now - sourceTime <= AirTraceDefaults.maximumSampleAgeSeconds else { invalidate(.stalePair); return }
        rawTrace.append(point)
        lastCaptureTimestamp = now
        state = .tracing
    }

    /// Camera source liveness is independent of Vision's asynchronous hand results.
    public mutating func observeSource(captureTimestamp: Double, generation: UInt64, now: Double,
                                      geometry currentGeometry: RenderGeometry) {
        guard handOnly else { return }
        if indexOnly || screenTouch, let drawingStartedAt, captureTimestamp.isFinite, captureTimestamp < drawingStartedAt { return }
        expireInputs(now: now, geometry: currentGeometry)
        guard state == .ready || state == .armed || state == .tracing else { return }
        let reason: AirTraceRejection?
        if generation != captureGeneration { reason = .generationChanged }
        else if !now.isFinite || !captureTimestamp.isFinite || captureTimestamp < 0 || now < captureTimestamp { reason = .invalidTimestamp }
        else if now - captureTimestamp > AirTraceDefaults.maximumSampleAgeSeconds { reason = .stalePair }
        else { reason = nil }
        if let reason {
            if state == .tracing { invalidate(reason) }
            return
        }
        lastSourceGazeTimestamp = max(lastSourceGazeTimestamp ?? captureTimestamp, captureTimestamp)
    }

    public mutating func consumeHand(_ hand: AirTraceHandSample?, now: Double,
                                     geometry currentGeometry: RenderGeometry) {
        guard handOnly, !indexOnly, !screenTouch else { return }
        guard currentGeometry == geometry else { invalidate(.geometryChanged); return }
        guard state == .ready || state == .tracing else { return }
        let sourceReason: AirTraceRejection? = lastSourceGazeTimestamp.map {
            now < $0 ? .invalidTimestamp : (now - $0 > AirTraceDefaults.maximumSampleAgeSeconds ? .stalePair : nil)
        } ?? .missingPair
        let reason = handRejection(hand, now: now) ?? sourceReason
        if let reason {
            if state == .tracing { invalidate(reason) }
            return
        }
        guard let hand else { return }
        consumeValidatedHand(hand)
    }

    /// Validate every source eye event, even when hand inference skips its frame.
    /// Invalid observations cannot be hidden by a later valid hand/gaze pair.
    @discardableResult
    public mutating func observeGaze(_ gaze: AirTraceGazeSample, now: Double,
                                    geometry currentGeometry: RenderGeometry) -> Bool {
        guard !handOnly else { return false }
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
        // A stationary touchscreen finger has no inference stream to expire; the camera must stay live.
        guard screenTouch || now - handTime <= AirTraceDefaults.maximumSampleAgeSeconds,
              now - sourceTime <= AirTraceDefaults.maximumSampleAgeSeconds else {
            invalidate(.stalePair)
            return
        }
    }

    /// `now` and both capture timestamps use the same monotonic clock; generation identifies the AR session run.
    public mutating func consume(hand: AirTraceHandSample?, gaze: AirTraceGazeSample?, now: Double,
                                 geometry currentGeometry: RenderGeometry) {
        guard !handOnly else { return }
        guard currentGeometry == geometry else { invalidate(.geometryChanged); return }
        guard state == .ready || state == .tracing else { return }
        if let reason = pairRejection(hand: hand, gaze: gaze, now: now) {
            if state == .tracing { invalidate(reason) }
            return
        }
        guard let hand, let gaze else { return } // Pair validation already checked both optional inputs.
        lastSourceGazeTimestamp = max(lastSourceGazeTimestamp ?? gaze.captureTimestamp, gaze.captureTimestamp)
        consumeValidatedHand(hand)
    }

    private mutating func consumeValidatedHand(_ hand: AirTraceHandSample) {
        let pinchDistance = hypot(hand.indexTip.x - hand.thumbTip.x, hand.indexTip.y - hand.thumbTip.y)
        if state == .ready {
            guard pinchDistance <= AirTraceDefaults.pinchCloseDiagonalFraction * geometry.diagonal else { return }
            state = .tracing
        }
        rawTrace.append(hand.indexTip)
        lastCaptureTimestamp = hand.captureTimestamp
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
        if let reason = handRejection(hand, now: now) { return reason }
        return gazeRejection(gaze)
    }

    private func handRejection(_ hand: AirTraceHandSample?, now: Double) -> AirTraceRejection? {
        guard let hand else { return .missingPair }
        guard now.isFinite, hand.captureTimestamp.isFinite, hand.captureTimestamp >= 0,
              now >= hand.captureTimestamp else { return .invalidTimestamp }
        guard now - hand.captureTimestamp <= AirTraceDefaults.maximumSampleAgeSeconds else { return .stalePair }
        guard captureGeneration == hand.generation else { return .generationChanged }
        if let lastCaptureTimestamp {
            guard hand.captureTimestamp > lastCaptureTimestamp else { return .duplicateCapture }
            guard hand.captureTimestamp - lastCaptureTimestamp <= AirTraceDefaults.maximumSampleAgeSeconds else { return .captureGap }
        }
        guard validHand(hand) else { return .invalidHand }
        return nil
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
        if screenTouch {
            var twiceArea = 0.0
            var previous = first
            for point in rawTrace.dropFirst() {
                twiceArea += ((previous.x - first.x) / geometry.width) * ((point.y - first.y) / geometry.height)
                    - ((point.x - first.x) / geometry.width) * ((previous.y - first.y) / geometry.height)
                previous = point
            }
            let boundingArea = ((maxX - minX) / geometry.width) * ((maxY - minY) / geometry.height)
            guard abs(twiceArea) / 2 > boundingArea * AirTraceDefaults.minimumTouchAreaBoundingFraction else {
                invalidate(.degenerateStroke); return
            }
        }
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
        drawingStartedAt = nil
    }
}
