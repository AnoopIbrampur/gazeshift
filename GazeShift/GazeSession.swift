import Foundation
import CoreGraphics
import GazeShiftCore

enum GazeRunPolicy {
    // Provisional collection minimum: enough distinct samples across each 1s fixation,
    // without allowing a single frame or a partial grid to define a personal fit.
    static let minimumTrainingSamples = 15
    static let recoverySamples = 3
    static let schedulerSeconds = 0.01
    static let trainingCoordinates = [0.15, 0.50, 0.85]
    static let evaluationSequence: [HeldOutTarget] = [.upperLeft, .upperRight, .centerControl, .lowerLeft, .lowerRight]
}

enum GazePhase: Equatable { case uncalibrated, calibrating, provisional, evaluating, evaluated, failed }
enum GazeDisplayState: Equatable { case uncalibrated, sceneUnavailable, unavailable, recovering(Int), outsideView, active }

struct GazeTarget: Equatable, Identifiable {
    let id: Int
    let normalized: ScreenPoint
    let label: String
}

/// Display calibration state, independent of camera-image UV mapping and rendering.
/// The only inference input is actual face-relative eye data; targets label training only.
struct GazeSession {
    private(set) var geometry: RenderGeometry?
    private(set) var phase: GazePhase = .uncalibrated
    private(set) var calibration: GazeCalibration?
    private(set) var report: HeldOutReport?
    private(set) var target: GazeTarget?
    private(set) var trainingIndex = 0
    private(set) var trainingCounts: [Int] = []
    private(set) var completedWindows: [HeldOutWindowResult] = []
    private(set) var message = "Not calibrated — choose a camera, then Calibrate"
    private(set) var recoveryCount = 0
    private var generation: UInt64 = 0
    private var mode: CaptureMode = .setupFront
    private var targetSerial = 0
    private var presentedAt: Double?
    private var trainingSamples: [CalibrationSample] = []
    private var currentSamples: [CalibrationSample] = []
    private var trainingSources = Set<Double>()
    private var latestObservation: GazeObservation?
    private var latestSourceTimestamp: Double?
    private var latestScene: FrameIdentity?
    private var displayReady = false
    private var lastRecoverySource: Double?
    private var window: HeldOutWindow?
    private var nextSlot = 0

    var currentTrainingCount: Int { currentSamples.count }
    var isRunning: Bool { phase == .calibrating || phase == .evaluating }

    mutating func configure(size: CGSize, scale: CGFloat, mode: CaptureMode, generation: UInt64, origin: CGPoint = .zero) {
        guard origin.x.isFinite, origin.y.isFinite else { invalidate("Display position unavailable"); geometry = nil; return }
        let next = try? RenderGeometry(width: Double(size.width), height: Double(size.height), scale: Double(scale),
                                       orientation: .portrait, mode: mode == .setupFront ? .frontSetup : .rearLive,
                                       viewingSetupID: "capture-generation-\(generation)-origin-\(origin.x)-\(origin.y)")
        guard next != geometry || generation != self.generation || mode != self.mode else { return }
        self.geometry = next
        self.mode = mode
        self.generation = generation
        invalidate("Not calibrated — camera or display setup changed")
    }

    mutating func invalidate(_ reason: String) {
        calibration = nil
        report = nil
        target = nil
        presentedAt = nil
        trainingSamples = []
        currentSamples = []
        trainingSources = []
        trainingCounts = []
        completedWindows = []
        latestObservation = nil
        latestSourceTimestamp = nil
        latestScene = nil
        lastRecoverySource = nil
        recoveryCount = 0
        window = nil
        phase = .uncalibrated
        message = reason
    }

    mutating func startCalibration() {
        guard geometry != nil else { message = "Display unavailable — calibration cannot start"; return }
        invalidate("Look at the white target; keep head and distance still")
        phase = .calibrating
        trainingIndex = 0
        presentTrainingTarget()
    }

    mutating func startEvaluation() {
        guard calibration != nil, geometry != nil, !isRunning else { return }
        report = nil
        completedWindows = []
        phase = .evaluating
        presentEvaluationTarget()
    }

    /// Called by the target overlay when SwiftUI installs this target. Stale callbacks
    /// cannot start a newer target. This is UI timing, not measured display latency.
    mutating func targetPresented(at now: Double, targetID: Int? = nil) {
        guard now.isFinite, isRunning, presentedAt == nil, let target,
              targetID == nil || targetID == target.id else { return }
        presentedAt = now
        if phase == .evaluating, let geometry {
            do {
                window = try HeldOutWindow(target: evaluationTarget, pass: evaluationPass,
                                          presentedAt: now, geometry: geometry)
                nextSlot = 0
            } catch { fail("Cannot start target window: \(error)") }
        }
    }

    mutating func receive(_ snapshot: CaptureSnapshot, now: Double) {
        guard snapshot.generation == generation, snapshot.mode == mode else { return }
        let packet = snapshot.renderPacket
        latestScene = packet.flatMap { item in
            item.mode == mode && item.identity.generation == generation && item.identity.isFresh(at: now) ? item.identity : nil
        }
        displayReady = snapshot.status == .ready
        guard let scene = latestScene, let raw = snapshot.rawEyes, let identity = snapshot.rawEyeIdentity,
              identity.generation == generation, identity.isFresh(at: now),
              identity.captureTimestamp == scene.captureTimestamp else {
            latestObservation = nil
            recoveryCount = 0
            return
        }
        // Preserve source identity separately from host time. Repeated delivery cannot
        // retimestamp a camera sample, add training samples, or advance live recovery.
        if let latestSourceTimestamp, identity.captureTimestamp <= latestSourceTimestamp { return }
        latestSourceTimestamp = identity.captureTimestamp
        let features = try? EyeFeatures.from(leftEye: double(raw.leftEyeTranslation), rightEye: double(raw.rightEyeTranslation),
                                            lookAtPoint: double(raw.lookAtPoint))
        let observation = GazeObservation(timestamp: identity.estimatedCaptureAt ?? identity.receivedAt,
                                          isTracked: raw.isTracked, leftBlink: raw.leftBlink.map(Double.init),
                                          rightBlink: raw.rightBlink.map(Double.init), features: features)
        latestObservation = observation
        if phase == .calibrating { collect(observation, source: identity.captureTimestamp, now: now) }
        if displayReady, let calibration, let geometry,
           calibration.livePrediction(observation: observation, now: now, geometry: geometry) != nil {
            if lastRecoverySource != identity.captureTimestamp {
                recoveryCount = min(recoveryCount + 1, GazeRunPolicy.recoverySamples)
                lastRecoverySource = identity.captureTimestamp
            }
        } else { recoveryCount = 0 }
    }

    mutating func tick(now: Double) {
        guard now.isFinite else { return }
        if GazeQuality.rejectionReason(observation: latestObservation, now: now) != nil
            || latestScene?.isFresh(at: now) != true { recoveryCount = 0 }
        guard let presentedAt else { return }
        if phase == .calibrating, now >= presentedAt + HeldOutPolicy.settlingSeconds + HeldOutPolicy.windowSeconds {
            finishTrainingTarget()
        } else if phase == .evaluating { advanceEvaluation(now: now) }
    }

    func marker(at now: Double) -> ScreenPoint? {
        guard phase == .provisional || phase == .evaluated,
              displayReady, recoveryCount >= GazeRunPolicy.recoverySamples,
              latestScene?.isFresh(at: now) == true, let calibration, let geometry else { return nil }
        return calibration.livePrediction(observation: latestObservation, now: now, geometry: geometry)
    }

    func displayState(at now: Double) -> GazeDisplayState {
        guard let calibration, let geometry else { return .uncalibrated }
        guard latestScene?.isFresh(at: now) == true else { return .sceneUnavailable }
        guard displayReady, GazeQuality.rejectionReason(observation: latestObservation, now: now) == nil,
              let features = latestObservation?.features,
              let prediction = try? calibration.predict(features: features, geometry: geometry) else { return .unavailable }
        guard geometry.contains(prediction) else { return .outsideView }
        return marker(at: now) == nil ? .recovering(recoveryCount) : .active
    }

    mutating func cancel() {
        guard isRunning else { return }
        target = nil
        presentedAt = nil
        window = nil
        phase = calibration == nil ? .uncalibrated : .provisional
        message = calibration == nil ? "Calibration canceled — no gaze marker" : "Test canceled — provisional calibration only"
    }

    mutating func recordEyeOnly(_ response: EyeOnlyResponse) {
        guard report != nil, let geometry else { return }
        do {
            report = try HeldOutReport(windows: completedWindows, geometry: geometry, eyeOnlyResponse: response)
        } catch { fail("Cannot update eye-only result: \(error)") }
    }

    private mutating func collect(_ observation: GazeObservation, source: Double, now: Double) {
        guard let presentedAt, let target, let geometry else { return }
        let start = presentedAt + HeldOutPolicy.settlingSeconds
        let end = start + HeldOutPolicy.windowSeconds
        guard observation.timestamp >= start, observation.timestamp < end,
              now >= start, now < end,
              GazeQuality.rejectionReason(observation: observation, now: now) == nil,
              let features = observation.features, trainingSources.insert(source).inserted else { return }
        currentSamples.append(CalibrationSample(features: features,
                                               target: ScreenPoint(x: target.normalized.x * geometry.width,
                                                                   y: target.normalized.y * geometry.height)))
    }

    private mutating func finishTrainingTarget() {
        guard currentSamples.count >= GazeRunPolicy.minimumTrainingSamples else {
            message = "Target \(trainingIndex + 1)/9: only \(currentSamples.count) valid samples — repeating"
            presentTrainingTarget()
            return
        }
        trainingCounts.append(currentSamples.count)
        trainingSamples.append(contentsOf: currentSamples)
        trainingIndex += 1
        guard trainingIndex == GazeRunPolicy.trainingCoordinates.count * GazeRunPolicy.trainingCoordinates.count else {
            presentTrainingTarget()
            return
        }
        guard let geometry else { fail("Display unavailable"); return }
        do {
            calibration = try GazeCalibration.fit(samples: trainingSamples, geometry: geometry)
            target = nil
            presentedAt = nil
            phase = .provisional
            recoveryCount = 0
            message = "Provisional calibration — run held-out test before claiming accuracy"
        } catch { fail("Calibration failed: \(error). Recalibrate with eye movement and a still head.") }
    }

    private mutating func advanceEvaluation(now: Double) {
        guard var current = window, let calibration else { return }
        while nextSlot < HeldOutPolicy.slots,
              now >= current.startsAt + Double(nextSlot) * HeldOutPolicy.slotSeconds {
            do { try current.record(slot: nextSlot, now: now, observation: latestObservation, calibration: calibration) }
            catch { fail("Evaluation slot failed: \(error)"); return }
            nextSlot += 1
        }
        window = current
        guard now >= current.endsAt else { return }
        completedWindows.append(current.finish())
        window = nil
        presentedAt = nil
        if completedWindows.count == GazeRunPolicy.evaluationSequence.count * HeldOutPolicy.passes {
            guard let geometry else { fail("Display unavailable"); return }
            do {
                report = try HeldOutReport(windows: completedWindows, geometry: geometry)
                phase = .evaluated
                target = nil
                message = "Evaluated — inspect the report, then check eye-only movement"
            } catch { fail("Evaluation failed: \(error)") }
        } else { presentEvaluationTarget() }
    }

    private var evaluationTarget: HeldOutTarget {
        GazeRunPolicy.evaluationSequence[completedWindows.count % GazeRunPolicy.evaluationSequence.count]
    }
    private var evaluationPass: Int { completedWindows.count / GazeRunPolicy.evaluationSequence.count + 1 }

    private mutating func presentTrainingTarget() {
        let positions = GazeRunPolicy.trainingCoordinates
        let point = ScreenPoint(x: positions[trainingIndex % positions.count], y: positions[trainingIndex / positions.count])
        currentSamples = []
        trainingSources = []
        setTarget(point, label: "Calibration \(trainingIndex + 1)/9")
    }

    private mutating func presentEvaluationTarget() {
        message = "Fixate white target — marker hidden during measurement"
        setTarget(evaluationTarget.normalized, label: "Test \(completedWindows.count + 1)/10 · pass \(evaluationPass)")
    }

    private mutating func setTarget(_ point: ScreenPoint, label: String) {
        targetSerial += 1
        target = GazeTarget(id: targetSerial, normalized: point, label: label)
        presentedAt = nil
    }

    private mutating func fail(_ detail: String) {
        target = nil
        presentedAt = nil
        window = nil
        phase = .failed
        message = detail
        recoveryCount = 0
    }

    private func double(_ value: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3(Double(value.x), Double(value.y), Double(value.z))
    }
}
