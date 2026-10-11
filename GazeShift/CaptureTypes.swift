import Foundation
import CoreGraphics
import CoreVideo
import simd

/// Same-frame ARKit face transform expressed in the active AR camera's coordinate system.
/// This is not physical-screen registration or a measured retinal/head stability score.
struct FaceCameraPose {
    let position: SIMD3<Float>
    let orientation: simd_quatf
    init?(cameraTransform: simd_float4x4, faceTransform: simd_float4x4) {
        let matrices = [cameraTransform, faceTransform]
        guard matrices.allSatisfy({ matrix in (0..<4).allSatisfy { column in
            (0..<4).allSatisfy { matrix[column][$0].isFinite }
        } }), simd_determinant(cameraTransform).isFinite, simd_determinant(cameraTransform) != 0 else { return nil }
        let relative = simd_inverse(cameraTransform) * faceTransform
        let rotation = simd_quatf(relative)
        let translation = relative.columns.3
        guard (0..<4).allSatisfy({ translation[$0].isFinite && rotation.vector[$0].isFinite }),
              simd_length(rotation.vector) > 0 else { return nil }
        position = SIMD3(translation.x, translation.y, translation.z)
        orientation = simd_normalize(rotation)
    }
    static func angularChangeDegrees(_ first: simd_quatf, _ next: simd_quatf) -> Double {
        // q and -q represent the same rotation; report the shortest relative angle.
        Double(2 * acos(min(1, abs(simd_dot(first.vector, next.vector))))) * 180 / .pi
    }
}

struct CaptureFrameDiagnostics {
    let identity: FrameIdentity
    /// AR delegate callbacks after the current run cutoff, including rejected scene frames.
    let sourceFrameCount: UInt64
    let pose: FaceCameraPose?
    let faceAnchorID: UUID?
    let configuredFPS: Int?
    let thermalState: String?
    init(identity: FrameIdentity, sourceFrameCount: UInt64, pose: FaceCameraPose? = nil,
         faceAnchorID: UUID? = nil, configuredFPS: Int? = nil, thermalState: String? = nil) {
        self.identity = identity
        self.sourceFrameCount = sourceFrameCount
        self.pose = pose
        self.faceAnchorID = faceAnchorID
        self.configuredFPS = configuredFPS
        self.thermalState = thermalState
    }
}

struct CaptureMainDelivery {
    let acceptedSnapshots: UInt64
    let acceptedFrames: UInt64
    let acceptedAt: TimeInterval
    let estimatedCaptureToMainAge: TimeInterval?
}

/// Sidecar bookkeeping only; CaptureModel's existing generation/sequence guard still decides acceptance.
struct CaptureDeliveryCounter {
    private var generation: UInt64?
    private var snapshots: UInt64 = 0
    private var frames: UInt64 = 0
    private var lastSource: TimeInterval?
    mutating func record(_ snapshot: CaptureSnapshot, at now: TimeInterval) -> CaptureSnapshot {
        if generation != snapshot.generation {
            generation = snapshot.generation
            snapshots = 0
            frames = 0
            lastSource = nil
        }
        snapshots &+= 1
        let identity = snapshot.frameDiagnostics?.identity.generation == snapshot.generation ? snapshot.frameDiagnostics?.identity : nil
        if let identity, identity.generation == generation,
           identity.captureTimestamp.isFinite, lastSource.map({ identity.captureTimestamp > $0 }) ?? true {
            frames &+= 1
            lastSource = identity.captureTimestamp
        }
        let captureAt = identity.map { $0.estimatedCaptureAt ?? $0.receivedAt }
        let age = captureAt.flatMap { time in
            now.isFinite && time.isFinite && now >= time ? now - time : nil
        }
        var next = snapshot
        next.mainDelivery = CaptureMainDelivery(acceptedSnapshots: snapshots, acceptedFrames: frames,
                                               acceptedAt: now, estimatedCaptureToMainAge: age)
        return next
    }
}

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
    var title: String { self == .setupFront ? "Front setup" : "Rear scene" }
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

/// Ordered sensing events, separate from display snapshots and their freshness filtering.
enum CaptureEvent {
    case source(identity: FrameIdentity, mode: CaptureMode)
    case eyes(EyeObservation?, identity: FrameIdentity, mode: CaptureMode)
    case hand(Result<HandObservation?, Error>, identity: FrameIdentity, mode: CaptureMode)
    case reset(generation: UInt64, mode: CaptureMode)
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
        case .ready: return "Live camera ready — eye tracking disabled"
        case .unsupported(let detail): return detail
        case .failed(let detail): return "Scene unavailable — \(detail)"
        }
    }
}

struct CaptureSupport {
    let frontFace: Bool
    let world: Bool
    let rearFace: Bool
    var text: String { "Front camera provider \(frontFace ? "yes" : "no") · Rear scene \(world ? "yes" : "no")" }
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
    /// Optional observational sidecars; never sensor quality or inference inputs.
    var frameDiagnostics: CaptureFrameDiagnostics? = nil
    var mainDelivery: CaptureMainDelivery? = nil
    /// Main-thread delivery can be delayed after capture validated a frame.
    /// Recheck every observation before an immutable update reaches the display.
    func forDisplay(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> CaptureSnapshot {
        let staleScene = renderPacket.map { $0.identity.generation != generation || !$0.identity.isFresh(at: now) } ?? false
        let safePacket = staleScene ? nil : renderPacket
        let validEyes = safePacket != nil && eyes?.isValid == true && eyeIdentity.map { $0.generation == generation && $0.isFresh(at: now) } == true
        let safeHand = safePacket == nil ? nil : hand.flatMap { $0.identity.generation == generation && $0.identity.isFresh(at: now) ? $0 : nil }
        let safeStatus: CaptureStatus = staleScene ? .sceneUnavailable : status
        let safeHandMessage = staleScene ? "Hand unavailable — stale source" : (hand != nil && safeHand == nil ? "Hand unavailable — stale result" : handMessage)
        let safeRawIdentity = rawEyeIdentity.flatMap { safePacket != nil && $0.generation == generation && $0.isFresh(at: now) ? $0 : nil }
        // Preserve matching diagnostics even when stale display input is removed, so late delivery stays measurable.
        let diagnostics = frameDiagnostics.flatMap { $0.identity.generation == generation && $0.identity == renderPacket?.identity ? $0 : nil }
        return CaptureSnapshot(sequence: sequence, generation: generation, mode: mode, status: safeStatus, support: support, renderPacket: safePacket, eyes: validEyes ? eyes : nil, eyeIdentity: validEyes ? eyeIdentity : nil, hand: safeHand, handMessage: safeHandMessage, rawEyes: safeRawIdentity == nil ? nil : rawEyes, rawEyeIdentity: safeRawIdentity, frameDiagnostics: diagnostics, mainDelivery: mainDelivery)
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
