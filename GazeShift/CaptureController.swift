import ARKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class CaptureModel: ObservableObject {
    @Published private(set) var snapshot: CaptureSnapshot = {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        return CaptureSnapshot(sequence: 0, generation: 0, mode: .setupFront, status: .paused, support: nil, renderPacket: nil, eyes: nil, eyeIdentity: nil, hand: nil, handMessage: "Hand unavailable")
        #endif
    }()
    let events = PassthroughSubject<CaptureEvent, Never>()
    private var deliveryCounter = CaptureDeliveryCounter()
    private lazy var controller = CaptureController(publish: { [weak self] next in
        DispatchQueue.main.async { [weak self] in self?.accept(next) }
    }, publishEvent: { [weak self] event in
        // The serial capture queue enqueues source/completion events in order on the main queue.
        DispatchQueue.main.async { [weak self] in self?.events.send(event) }
    })
    func start(_ mode: CaptureMode) { controller.start(mode) }
    func retry() { controller.start(snapshot.mode) }
    func stop() { controller.stop() }
    func layout(_ size: CGSize, scale: CGFloat) { controller.layout(size, scale: scale) }
    func rendererFailed(_ message: String) { controller.rendererFailed(message) }
    private func accept(_ next: CaptureSnapshot) {
        guard next.generation >= snapshot.generation, next.sequence > snapshot.sequence else { return }
        let now = ProcessInfo.processInfo.systemUptime
        snapshot = deliveryCounter.record(next.forDisplay(at: now), at: now)
    }
}

/// Owns one session; all mutable capture/worker state lives on `queue`.
final class CaptureController: NSObject, ARSessionDelegate {
    private let queue = DispatchQueue(label: "com.gazeshift.capture", qos: .userInitiated)
    private lazy var session: ARSession = {
        let session = ARSession()
        session.delegate = self
        session.delegateQueue = queue
        return session
    }()
    private let publish: (CaptureSnapshot) -> Void
    private let publishEvent: (CaptureEvent) -> Void
    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0
    private var mode: CaptureMode = .setupFront
    private var status: CaptureStatus = {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        return .paused
        #endif
    }()
    private var support: CaptureSupport?
    private var viewport: CGSize = .zero
    private var displayScale: CGFloat = 0
    private var running = false
    private var cutoffTimestamp: TimeInterval = -.infinity
    private var freshness = CaptureFreshness(generation: 0)
    private var packet: RenderPacket?
    private var eyes: EyeObservation?
    private var eyeIdentity: FrameIdentity?
    private var rawEyes: EyeObservation?
    private var rawEyeIdentity: FrameIdentity?
    private var hand: HandObservation?
    private var handMessage = "Hand unavailable"
    private var handFreshness = HandResultFreshness(generation: 0)
    private var captureClock = CaptureClock()
    private var sourceFrameCount: UInt64 = 0
    private var frameDiagnostics: CaptureFrameDiagnostics?
    private var configuredFPS: Int?
    private var watchdog: DispatchSourceTimer?
    private lazy var handTracker = HandTracker(ownerQueue: queue) { [weak self] item, result in self?.handFinished(item, result: result) }

    init(publish: @escaping (CaptureSnapshot) -> Void, publishEvent: @escaping (CaptureEvent) -> Void) {
        self.publish = publish
        self.publishEvent = publishEvent
        super.init()
    }
    deinit { watchdog?.cancel() }

    func start(_ requestedMode: CaptureMode) {
        queue.async { [weak self] in
            guard let self else { return }
            self.mode = requestedMode
            #if targetEnvironment(simulator)
            self.invalidate(status: .simulator)
            self.emit()
            #else
            self.session.pause()
            self.running = false
            self.cutoffTimestamp = self.session.currentFrame?.timestamp ?? self.cutoffTimestamp
            self.invalidate(status: .sceneUnavailable)
            self.support = CaptureSupport(frontFace: ARFaceTrackingConfiguration.isSupported, world: ARWorldTrackingConfiguration.isSupported, rearFace: ARWorldTrackingConfiguration.supportsUserFaceTracking)
            self.ensureWatchdog()
            let token = self.generation
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.runAuthorized(token: token)
            case .notDetermined:
                self.status = .permissionRequired
                self.emit()
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    self?.queue.async {
                        guard let self, self.generation == token else { return }
                        if granted { self.runAuthorized(token: token) }
                        else { self.status = .permissionDenied; self.emit() }
                    }
                }
            default: self.status = .permissionDenied; self.emit()
            }
            #endif
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            #if !targetEnvironment(simulator)
            self.session.pause()
            #endif
            self.running = false
            #if targetEnvironment(simulator)
            self.invalidate(status: .simulator)
            #else
            self.invalidate(status: .paused)
            #endif
            self.emit()
        }
    }

    func layout(_ size: CGSize, scale: CGFloat) {
        queue.async { [weak self] in
            guard let self, self.viewport != size || self.displayScale != scale else { return }
            self.viewport = size
            self.displayScale = scale
            #if !targetEnvironment(simulator)
            if self.running { self.cutoffTimestamp = self.session.currentFrame?.timestamp ?? self.cutoffTimestamp }
            #endif
            self.invalidate(status: self.running ? .sceneUnavailable : self.status)
            self.emit()
        }
    }

    func rendererFailed(_ message: String) {
        queue.async { [weak self] in
            guard let self else { return }
            #if !targetEnvironment(simulator)
            self.session.pause()
            #endif
            self.running = false
            self.invalidate(status: .failed(message))
            self.emit()
        }
    }

    private func runAuthorized(token: UInt64) {
        guard token == generation, let support else { return }
        let configuration: ARConfiguration
        if mode == .setupFront {
            guard support.frontFace else { status = .unsupported("Front face tracking unsupported on this device"); emit(); return }
            let front = ARFaceTrackingConfiguration()
            front.isLightEstimationEnabled = false
            configuration = front
        } else {
            guard support.world && support.rearFace else { status = .unsupported("Rear scene + eye tracking unsupported on this device"); emit(); return }
            let rear = ARWorldTrackingConfiguration()
            rear.userFaceTrackingEnabled = true
            rear.isLightEstimationEnabled = false
            configuration = rear
        }
        running = true
        configuredFPS = configuration.videoFormat.framesPerSecond
        status = .sceneUnavailable
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        emit()
    }

    private func invalidate(status: CaptureStatus) {
        generation &+= 1
        freshness = CaptureFreshness(generation: generation)
        packet = nil
        eyes = nil
        rawEyes = nil
        rawEyeIdentity = nil
        eyeIdentity = nil
        hand = nil
        handFreshness = HandResultFreshness(generation: generation)
        captureClock = CaptureClock()
        sourceFrameCount = 0
        frameDiagnostics = nil
        handMessage = mode == .setupFront ? "Hand unavailable — waiting for both tips" : "Hand tracking off in rear mode"
        handTracker.invalidatePending()
        self.status = status
        publishEvent(.reset(generation: generation, mode: mode))
    }

    private func ensureWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: CaptureLimits.watchdogInterval)
        timer.setEventHandler { [weak self] in self?.checkFreshness() }
        timer.resume()
        watchdog = timer
    }

    private func checkFreshness() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var changed = false
        if freshness.expireScene(at: now), packet != nil || eyes != nil || hand != nil {
            packet = nil
            eyes = nil
            rawEyes = nil
            rawEyeIdentity = nil
            eyeIdentity = nil
            hand = nil
            status = .sceneUnavailable
            handMessage = "Hand unavailable — stale source"
            changed = true
        }
        if let hand, !hand.identity.isFresh(at: now) {
            self.hand = nil
            handMessage = "Hand unavailable — stale result"
            changed = true
        }
        if changed { emit() }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, frame.timestamp > cutoffTimestamp else { return }
        sourceFrameCount &+= 1
        let now = ProcessInfo.processInfo.systemUptime
        guard let identity = captureClock.identity(generation: generation, captureTimestamp: frame.timestamp, receivedAt: now) else { return }
        guard let geometry = DisplayGeometry(viewport: viewport, displayTransform: frame.displayTransform(for: .portrait, viewportSize: viewport), orientation: .right, mirrored: mode == .setupFront) else {
            invalidate(status: .sceneUnavailable)
            emit()
            return
        }
        guard CVPixelBufferGetPixelFormatType(frame.capturedImage) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
            running = false
            session.pause()
            invalidate(status: .failed("Unsupported camera pixel format"))
            emit()
            return
        }
        guard freshness.acceptScene(identity, now: now) else { return }
        packet = RenderPacket(identity: identity, image: frame.capturedImage, geometry: geometry, mode: mode)
        // Read anchors from this exact frame. No cached anchors get a fresh timestamp.
        let face = frame.anchors.first { $0 is ARFaceAnchor } as? ARFaceAnchor
        let currentEyes = face.map(Self.eyeObservation)
        frameDiagnostics = CaptureFrameDiagnostics(identity: identity, sourceFrameCount: sourceFrameCount,
            pose: face.flatMap { $0.isTracked ? FaceCameraPose(cameraTransform: frame.camera.transform, faceTransform: $0.transform) : nil },
            faceAnchorID: face?.identifier, configuredFPS: configuredFPS, thermalState: thermalStateText)
        rawEyes = currentEyes
        rawEyeIdentity = identity
        publishEvent(.eyes(currentEyes, identity: identity, mode: mode))
        freshness.acceptEyes(currentEyes, identity: identity, now: now)
        eyes = currentEyes?.isValid == true ? currentEyes : nil
        eyeIdentity = eyes == nil ? nil : identity
        status = freshness.trackingAvailable ? .ready : (freshness.recoveryCount > 0 ? .recovering(freshness.recoveryCount) : .trackingUnavailable)
        if mode == .setupFront { handTracker.submit(HandWork(identity: identity, image: frame.capturedImage, geometry: geometry)) }
        emit()
    }

    private static func eyeObservation(_ face: ARFaceAnchor) -> EyeObservation {
        let left = face.leftEyeTransform.columns.3
        let right = face.rightEyeTransform.columns.3
        return EyeObservation(lookAtPoint: face.lookAtPoint, leftEyeTranslation: SIMD3(left.x, left.y, left.z), rightEyeTranslation: SIMD3(right.x, right.y, right.z), leftBlink: face.blendShapes[.eyeBlinkLeft]?.floatValue, rightBlink: face.blendShapes[.eyeBlinkRight]?.floatValue, isTracked: face.isTracked)
    }

    private var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private func handFinished(_ item: HandWork, result: Result<HandObservation?, Error>) {
        let now = ProcessInfo.processInfo.systemUptime
        guard running, mode == .setupFront, item.identity.generation == generation else { return }
        // Even a stale, empty or failed current-run completion must invalidate an active stroke.
        publishEvent(.hand(result, identity: item.identity, mode: mode))
        guard handFreshness.accept(item.identity, now: now) else { return }
        // A fresh completion is usable even if a newer frame is waiting; no output starvation.
        switch result {
        case .success(let observation):
            hand = observation
            handMessage = observation == nil ? "Hand unavailable — show index and thumb tips" : "Hand cursor active (2D image landmarks)"
        case .failure(let error):
            hand = nil
            handMessage = "Hand unavailable — Vision: \(error.localizedDescription)"
        }
        emit()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        running = false
        session.pause()
        invalidate(status: .failed(error.localizedDescription))
        emit()
    }
    func sessionWasInterrupted(_ session: ARSession) {
        running = false
        invalidate(status: .paused)
        emit()
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        invalidate(status: .paused)
        emit()
    }

    private func emit() {
        sequence &+= 1
        publish(CaptureSnapshot(sequence: sequence, generation: generation, mode: mode, status: status, support: support, renderPacket: packet, eyes: eyes, eyeIdentity: eyeIdentity, hand: hand, handMessage: handMessage, rawEyes: rawEyes, rawEyeIdentity: rawEyeIdentity, frameDiagnostics: frameDiagnostics))
    }
}
