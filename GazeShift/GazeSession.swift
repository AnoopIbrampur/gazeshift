import Foundation
import CoreGraphics
import GazeShiftCore
import simd

/// Bounded observational summaries of distinct consumed camera frames, independent of gaze acceptance.
struct GazeWindowDiagnostics {
    private(set) var consumedFrames = 0
    private(set) var poseCount = 0
    private(set) var metadataFrames = 0
    private var latestSource: Double?
    private var firstCaptureAt: Double?
    private var lastCaptureAt: Double?
    private var firstSourceCount: UInt64?
    private var lastSourceCount: UInt64?
    private var firstDelivery: CaptureMainDelivery?
    private var lastDelivery: CaptureMainDelivery?
    private var ageCount = 0
    private var ageSum = 0.0
    private var maximumAge = 0.0
    private var positionSum = SIMD3<Float>.zero
    private var minimumPosition: SIMD3<Float>?
    private var maximumPosition: SIMD3<Float>?
    private var firstOrientation: simd_quatf?
    private var lastOrientation: simd_quatf?
    private(set) var maximumOrientationChangeDegrees = 0.0
    private var firstAnchor: UUID?
    private var lastAnchor: UUID?
    private var anchorCount = 0
    private var anchorChanges = 0
    private var firstFPS: Int?
    private var lastFPS: Int?
    private var firstThermal: String?
    private var lastThermal: String?
    private var thermalChanges = 0
    private var lastTick: Double?
    private(set) var maximumTickGap: Double?

    var sourceFrameSpan: UInt64? { span(firstSourceCount, lastSourceCount) }
    var mainFrameSpan: UInt64? { span(firstDelivery?.acceptedFrames, lastDelivery?.acceptedFrames) }
    var mainSnapshotSpan: UInt64? { span(firstDelivery?.acceptedSnapshots, lastDelivery?.acceptedSnapshots) }
    var meanPosition: SIMD3<Float>? { poseCount == 0 ? nil : positionSum / Float(poseCount) }
    var positionSpan: SIMD3<Float>? {
        guard let minimumPosition, let maximumPosition else { return nil }
        return maximumPosition - minimumPosition
    }

    mutating func beginTicks(at now: Double) { lastTick = now }
    mutating func tick(at now: Double) {
        if let lastTick, now >= lastTick { maximumTickGap = max(maximumTickGap ?? 0, now - lastTick) }
        lastTick = now
    }

    mutating func observe(_ snapshot: CaptureSnapshot, now: Double, startsAt: Double, endsAt: Double, generation: UInt64) {
        guard snapshot.generation == generation,
              let identity = snapshot.renderPacket?.identity ?? snapshot.rawEyeIdentity ?? snapshot.frameDiagnostics?.identity,
              identity.generation == generation else { return }
        let metadata = snapshot.frameDiagnostics.flatMap { $0.identity == identity ? $0 : nil }
        let captureAt = identity.estimatedCaptureAt ?? identity.receivedAt
        guard captureAt.isFinite, now.isFinite, identity.captureTimestamp.isFinite,
              captureAt >= startsAt, captureAt < endsAt, now >= startsAt, now < endsAt,
              latestSource == nil || identity.captureTimestamp > latestSource! else { return }
        latestSource = identity.captureTimestamp
        consumedFrames += 1
        guard let metadata else { return }
        metadataFrames += 1
        if firstCaptureAt == nil { firstCaptureAt = captureAt }
        lastCaptureAt = captureAt
        if firstSourceCount == nil { firstSourceCount = metadata.sourceFrameCount }
        lastSourceCount = metadata.sourceFrameCount
        if let delivery = snapshot.mainDelivery, delivery.acceptedAt.isFinite, delivery.acceptedAt >= identity.receivedAt {
            if firstDelivery == nil { firstDelivery = delivery }
            lastDelivery = delivery
            if let age = delivery.estimatedCaptureToMainAge, age.isFinite, age >= 0 {
                ageCount += 1
                ageSum += age
                maximumAge = max(maximumAge, age)
            }
        }
        if let fps = metadata.configuredFPS, fps > 0 {
            if firstFPS == nil { firstFPS = fps }
            lastFPS = fps
        }
        if let thermal = metadata.thermalState {
            if let lastThermal, lastThermal != thermal { thermalChanges += 1 }
            if firstThermal == nil { firstThermal = thermal }
            lastThermal = thermal
        }
        if let anchor = metadata.faceAnchorID {
            anchorCount += 1
            if let lastAnchor, lastAnchor != anchor { anchorChanges += 1 }
            if firstAnchor == nil { firstAnchor = anchor }
            lastAnchor = anchor
        }
        guard let pose = metadata.pose else { return }
        poseCount += 1
        positionSum += pose.position
        minimumPosition = minimumPosition.map { simd_min($0, pose.position) } ?? pose.position
        maximumPosition = maximumPosition.map { simd_max($0, pose.position) } ?? pose.position
        if firstOrientation == nil { firstOrientation = pose.orientation }
        if let firstOrientation {
            maximumOrientationChangeDegrees = max(maximumOrientationChangeDegrees, FaceCameraPose.angularChangeDegrees(firstOrientation, pose.orientation))
        }
        lastOrientation = pose.orientation
    }

    var reportLines: [String] {
        let source = sourceFrameSpan.map(String.init) ?? "unavailable"
        let mainFrames = mainFrameSpan.map(String.init) ?? "unavailable"
        let snapshots = mainSnapshotSpan.map(String.init) ?? "unavailable"
        let age = ageCount > 0 ? String(format: "estimated capture→main age mean %.1fms, max %.1fms (%d frames)", ageSum / Double(ageCount) * 1000, maximumAge * 1000, ageCount) : "capture→main age unavailable"
        let ticks = maximumTickGap.map { String(format: "max evaluation tick gap %.1fms (includes settle/completion)", $0 * 1000) } ?? "evaluation tick gap unavailable"
        var lines = [
            "  Delivery observed span [\(time(firstCaptureAt)), \(time(lastCaptureAt))] host capture seconds: source callbacks \(source); main acceptance span [\(time(firstDelivery?.acceptedAt)), \(time(lastDelivery?.acceptedAt))]: frames \(mainFrames), snapshots \(snapshots); GazeSession consumed \(consumedFrames) unique frames, metadata \(metadataFrames)/\(consumedFrames).",
            "  \(age); \(ticks). Configured FPS \(firstFPS.map(String.init) ?? "unavailable")→\(lastFPS.map(String.init) ?? "unavailable"); thermal \(firstThermal ?? "unavailable")→\(lastThermal ?? "unavailable"), changes \(thermalChanges).",
            "  Anchor \(firstAnchor?.uuidString ?? "unavailable")→\(lastAnchor?.uuidString ?? "unavailable"), changes \(anchorChanges), identity present \(anchorCount)/\(consumedFrames)."
        ]
        if let meanPosition, let positionSpan, let firstOrientation, let lastOrientation {
            lines.append("  Face-camera pose \(poseCount)/\(consumedFrames): mean xyz \(vector(meanPosition)), xyz span \(vector(positionSpan)); quaternion xyzw first \(quaternion(firstOrientation)), last \(quaternion(lastOrientation)); max change from first \(String(format: "%.2f", maximumOrientationChangeDegrees))°.")
        } else { lines.append("  Face-camera pose unavailable (0/\(consumedFrames) measured).") }
        return lines
    }

    private func span(_ first: UInt64?, _ last: UInt64?) -> UInt64? {
        guard let first, let last, last >= first else { return nil }
        return last - first + 1
    }
    private func time(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "unavailable" }
    private func vector(_ value: SIMD3<Float>) -> String { String(format: "(%.4f, %.4f, %.4f)", value.x, value.y, value.z) }
    private func quaternion(_ value: simd_quatf) -> String {
        String(format: "(%.4f, %.4f, %.4f, %.4f)", value.vector.x, value.vector.y, value.vector.z, value.vector.w)
    }
}

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
    private(set) var trainingFeatureSummaries: [EyeFeatureSummary?] = []
    private(set) var trainingDiagnostics: [GazeWindowDiagnostics] = []
    private(set) var evaluationDiagnostics: [GazeWindowDiagnostics] = []
    private var currentDiagnostics = GazeWindowDiagnostics()
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
        // The setup ID names the PHYSICAL display placement only. The capture generation is not physical;
        // a new generation still invalidates calibration through the guard below, but keeping it out of the
        // ID lets core `retainedForModeTransition` accept the deliberate same-display front→rear handoff.
        let next = try? RenderGeometry(width: Double(size.width), height: Double(size.height), scale: Double(scale),
                                       orientation: .portrait, mode: mode == .setupFront ? .frontSetup : .rearLive,
                                       viewingSetupID: "viewport-origin-\(origin.x)-\(origin.y)")
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
        trainingFeatureSummaries = []
        trainingDiagnostics = []
        evaluationDiagnostics = []
        currentDiagnostics = GazeWindowDiagnostics()
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
        evaluationDiagnostics = []
        presentEvaluationTarget()
    }

    /// Called by the target overlay when SwiftUI installs this target. Stale callbacks
    /// cannot start a newer target. This is UI timing, not measured display latency.
    mutating func targetPresented(at now: Double, targetID: Int? = nil) {
        guard now.isFinite, isRunning, presentedAt == nil, let target,
              targetID == nil || targetID == target.id else { return }
        presentedAt = now
        currentDiagnostics = GazeWindowDiagnostics()
        if phase == .evaluating { currentDiagnostics.beginTicks(at: now) }
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
        if isRunning, let presentedAt {
            let start = presentedAt + HeldOutPolicy.settlingSeconds
            currentDiagnostics.observe(snapshot, now: now, startsAt: start,
                                       endsAt: start + HeldOutPolicy.windowSeconds, generation: generation)
        }
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
        } else if phase == .evaluating {
            currentDiagnostics.tick(at: now)
            advanceEvaluation(now: now)
        }
    }

    func marker(at now: Double) -> ScreenPoint? {
        guard phase == .provisional || phase == .evaluated,
              displayReady, recoveryCount >= GazeRunPolicy.recoverySamples,
              latestScene?.isFresh(at: now) == true, let calibration, let geometry else { return nil }
        return calibration.livePrediction(observation: latestObservation, now: now, geometry: geometry)
    }

    /// Unvalidated gaze demo ONLY. Same phase, capture, scene-freshness and eye-quality rules as `marker`,
    /// but a finite off-screen prediction is pinned to the nearest view edge instead of hidden, so an
    /// inaccurate fit still drives the demo. Blinks, lost eyes and stale frames still return nil.
    func clampedDemoMarker(at now: Double) -> ScreenPoint? {
        guard phase == .provisional || phase == .evaluated, displayReady,
              latestScene?.isFresh(at: now) == true, let calibration, let geometry,
              GazeQuality.rejectionReason(observation: latestObservation, now: now) == nil,
              let features = latestObservation?.features,
              let prediction = try? calibration.predict(features: features, geometry: geometry),
              prediction.isFinite else { return nil }
        return ScreenPoint(x: min(max(prediction.x, 0), geometry.width),
                           y: min(max(prediction.y, 0), geometry.height))
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
        trainingFeatureSummaries.append(EyeFeatureSummary(features: currentSamples.map(\.features)))
        trainingDiagnostics.append(currentDiagnostics)
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
        evaluationDiagnostics.append(currentDiagnostics)
        window = nil
        presentedAt = nil
        currentDiagnostics = GazeWindowDiagnostics()
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
