import Foundation
import CoreGraphics
import CoreVideo

/// Provisional demonstration limits from the build protocol, not measured accuracy.
/// The blink cutoff is an exploratory rejection rule and needs device validation.
enum CaptureLimits {
    static let maximumAge: TimeInterval = 0.250
    static let minimumHandJointConfidence: Float = 0.5
    static let recoverySampleCount = 3
    static let blinkRejectionThreshold: Float = 0.7
    static let watchdogInterval: TimeInterval = 0.05
}

enum CaptureMode: String, CaseIterable {
    case setupFront
    case liveRear
    var title: String { self == .setupFront ? "Front setup" : "Rear + eyes" }
}

struct FrameIdentity: Equatable {
    let generation: UInt64
    let captureTimestamp: TimeInterval
    /// Host monotonic receipt time. Age uses this clock, never mixed epochs.
    let receivedAt: TimeInterval
    let estimatedCaptureAt: TimeInterval?
    init(generation: UInt64, captureTimestamp: TimeInterval, receivedAt: TimeInterval, estimatedCaptureAt: TimeInterval? = nil) {
        self.generation = generation
        self.captureTimestamp = captureTimestamp
        self.receivedAt = receivedAt
        self.estimatedCaptureAt = estimatedCaptureAt
    }
    func isFresh(at now: TimeInterval) -> Bool {
        let captureAt = estimatedCaptureAt ?? receivedAt
        let age = now - captureAt
        return captureTimestamp.isFinite && receivedAt.isFinite && captureAt.isFinite && now.isFinite
            && now >= receivedAt && captureAt <= receivedAt && age >= 0 && age <= CaptureLimits.maximumAge
    }
}

struct EyeObservation {
    let lookAtPoint: SIMD3<Float>
    let leftEyeTranslation: SIMD3<Float>
    let rightEyeTranslation: SIMD3<Float>
    let leftBlink: Float?
    let rightBlink: Float?
    /// ARKit transform validity, not an eye-tracking confidence score.
    let isTracked: Bool
    var isValid: Bool {
        isTracked && [lookAtPoint, leftEyeTranslation, rightEyeTranslation].allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        && [leftBlink, rightBlink].allSatisfy { $0.map { $0.isFinite && $0 < CaptureLimits.blinkRejectionThreshold } ?? true }
    }
}

struct HandObservation {
    let identity: FrameIdentity
    /// Canonical normalized display coordinates, origin at top left.
    let indexTip: CGPoint
    let thumbTip: CGPoint
    let indexConfidence: Float
    let thumbConfidence: Float
}

struct RenderPacket {
    let identity: FrameIdentity
    let image: CVPixelBuffer
    let geometry: DisplayGeometry
    let mode: CaptureMode
}

enum CaptureStatus: Equatable {
    case simulator
    case paused
    case permissionRequired
    case permissionDenied
    case sceneUnavailable
    case trackingUnavailable
    case recovering(Int)
    case ready
    case unsupported(String)
    case failed(String)
    var text: String {
        switch self {
        case .simulator: return "Simulator — camera, eye and hand tracking unavailable"
        case .paused: return "Paused"
        case .permissionRequired: return "Camera permission required"
        case .permissionDenied: return "Camera permission denied — allow Camera in Settings, then Retry"
        case .sceneUnavailable: return "Scene unavailable"
        case .trackingUnavailable: return "Tracking unavailable — original view"
        case .recovering(let count): return "Tracking recovering (\(count)/\(CaptureLimits.recoverySampleCount)) — original view"
        case .ready: return "Original view — raw tracking active"
        case .unsupported(let detail): return detail
        case .failed(let detail): return "Scene unavailable — \(detail)"
        }
    }
}

struct CaptureSupport {
    let frontFace: Bool
    let world: Bool
    let rearFace: Bool
    var text: String { "Front face \(frontFace ? "yes" : "no") · Rear world \(world ? "yes" : "no") · Rear eyes \(rearFace ? "yes" : "no")" }
}

struct CaptureSnapshot {
    let sequence: UInt64
    let generation: UInt64
    let mode: CaptureMode
    let status: CaptureStatus
    let support: CaptureSupport?
    let renderPacket: RenderPacket?
    let eyes: EyeObservation?
    let eyeIdentity: FrameIdentity?
    let hand: HandObservation?
    let handMessage: String
    /// Evaluation-only metadata; never used directly as a rendered gaze point.
    /// Retain invalid eyes so held-out rejection reasons remain truthful.
    var rawEyes: EyeObservation? = nil
    var rawEyeIdentity: FrameIdentity? = nil
    /// Main-thread delivery can be delayed after capture validated a frame.
    /// Recheck every observation before an immutable update reaches the display.
    func forDisplay(at now: TimeInterval) -> CaptureSnapshot {
        let staleScene = renderPacket.map { $0.identity.generation != generation || !$0.identity.isFresh(at: now) } ?? false
        let safePacket = staleScene ? nil : renderPacket
        let validEyes = safePacket != nil && eyes?.isValid == true && eyeIdentity.map { $0.generation == generation && $0.isFresh(at: now) } == true
        let safeHand = safePacket == nil ? nil : hand.flatMap { $0.identity.generation == generation && $0.identity.isFresh(at: now) ? $0 : nil }
        let safeStatus: CaptureStatus = staleScene ? .sceneUnavailable : (safePacket != nil && !validEyes ? .trackingUnavailable : status)
        let safeHandMessage = staleScene ? "Hand unavailable — stale source" : (hand != nil && safeHand == nil ? "Hand unavailable — stale result" : handMessage)
        let safeRawIdentity = rawEyeIdentity.flatMap { safePacket != nil && $0.generation == generation && $0.isFresh(at: now) ? $0 : nil }
        return CaptureSnapshot(sequence: sequence, generation: generation, mode: mode, status: safeStatus, support: support, renderPacket: safePacket, eyes: validEyes ? eyes : nil, eyeIdentity: validEyes ? eyeIdentity : nil, hand: safeHand, handMessage: safeHandMessage, rawEyes: safeRawIdentity == nil ? nil : rawEyes, rawEyeIdentity: safeRawIdentity)
    }
    static let simulator = CaptureSnapshot(sequence: 0, generation: 0, mode: .setupFront, status: .simulator, support: nil, renderPacket: nil, eyes: nil, eyeIdentity: nil, hand: nil, handMessage: "Hand tracking unavailable")
}

/// All mutation is owned by CaptureController's serial delegate queue.
struct CaptureFreshness {
    let generation: UInt64
    private(set) var recoveryCount = 0
    private(set) var trackingAvailable = false
    private var lastSceneTimestamp: TimeInterval = -.infinity
    private var lastSceneReceipt: TimeInterval?
    private var lastEyeTimestamp: TimeInterval = -.infinity

    mutating func acceptScene(_ identity: FrameIdentity, now: TimeInterval) -> Bool {
        guard identity.generation == generation, identity.isFresh(at: now), identity.captureTimestamp > lastSceneTimestamp else { return false }
        lastSceneTimestamp = identity.captureTimestamp
        lastSceneReceipt = identity.estimatedCaptureAt ?? identity.receivedAt
        return true
    }

    mutating func acceptEyes(_ eyes: EyeObservation?, identity: FrameIdentity, now: TimeInterval) {
        guard identity.generation == generation else { return }
        guard identity.isFresh(at: now), eyes?.isValid == true else {
            recoveryCount = 0
            trackingAvailable = false
            return
        }
        guard identity.captureTimestamp > lastEyeTimestamp else { return }
        lastEyeTimestamp = identity.captureTimestamp
        recoveryCount = min(recoveryCount + 1, CaptureLimits.recoverySampleCount)
        trackingAvailable = recoveryCount == CaptureLimits.recoverySampleCount
    }

    mutating func expireScene(at now: TimeInterval) -> Bool {
        guard let receipt = lastSceneReceipt, now.isFinite, now >= receipt, now - receipt <= CaptureLimits.maximumAge else {
            recoveryCount = 0
            trackingAvailable = false
            return true
        }
        return false
    }
}

/// Queue bookkeeping is separate from Vision so boundedness is testable without sensors.
struct NewestWorkQueue<Item> {
    private(set) var inFlight: Item?
    private(set) var pending: Item?
    mutating func offer(_ item: Item) -> Item? {
        guard inFlight == nil else { pending = item; return nil }
        inFlight = item
        return item
    }
    mutating func complete() -> Item? {
        inFlight = pending
        pending = nil
        return inFlight
    }
    mutating func clearPending() { pending = nil }
}

/// Converts elapsed source time to host monotonic time without assuming equal epochs.
struct CaptureClock {
    private var anchorCapture: TimeInterval?
    private var anchorReceipt: TimeInterval?
    mutating func identity(generation: UInt64, captureTimestamp: TimeInterval, receivedAt: TimeInterval) -> FrameIdentity? {
        guard captureTimestamp.isFinite, receivedAt.isFinite else { return nil }
        if anchorCapture == nil { anchorCapture = captureTimestamp; anchorReceipt = receivedAt }
        guard let anchorCapture, let anchorReceipt, captureTimestamp >= anchorCapture else { return nil }
        // Only elapsed source time is compared with elapsed host time. A delayed
        // callback cannot make an older captured frame fresh by assigning receipt time.
        let estimate = min(receivedAt, anchorReceipt + captureTimestamp - anchorCapture)
        return FrameIdentity(generation: generation, captureTimestamp: captureTimestamp, receivedAt: receivedAt, estimatedCaptureAt: estimate)
    }
}

struct HandResultFreshness {
    let generation: UInt64
    private var lastPublished: TimeInterval = -.infinity
    mutating func accept(_ identity: FrameIdentity, now: TimeInterval) -> Bool {
        guard identity.generation == generation, identity.isFresh(at: now), identity.captureTimestamp > lastPublished else { return false }
        lastPublished = identity.captureTimestamp
        return true
    }
}
