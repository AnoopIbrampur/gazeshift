import Foundation
import GazeShiftCore

public enum CalibrationRunPolicy {
    /// Nine training targets at normalized .15/.50/.85 in the measured viewport.
    public static let trainingAxis: [Double] = [0.15, 0.5, 0.85]
    public static let settleSeconds = HeldOutPolicy.settlingSeconds
    public static let captureSeconds = 1.0
    // Provisional engineering minimum mirroring the held-out distinct-sample gate; tune on device.
    public static let minimumTrainingSamplesPerTarget = HeldOutPolicy.minimumDistinctPredictions
    /// Center control interleaved inside each pass (never first or last); order differs between passes.
    public static let heldOutOrder: [[HeldOutTarget]] = [
        [.upperLeft, .lowerRight, .centerControl, .upperRight, .lowerLeft],
        [.lowerLeft, .upperRight, .centerControl, .lowerRight, .upperLeft]
    ]

    public static var trainingTargets: [ScreenPoint] {
        trainingAxis.flatMap { y in trainingAxis.map { x in ScreenPoint(x: x, y: y) } }
    }
}

public enum CalibrationStage: Equatable, Sendable { case settling, capturing }

public enum CalibrationRunFailure: Equatable, Sendable {
    case insufficientTrainingSamples(targetIndex: Int, validSamples: Int)
    case fitFailed(String)
    case geometryChanged
    case protocolError(String)

    public var text: String {
        switch self {
        case let .insufficientTrainingSamples(index, valid):
            "Target \(index + 1): only \(valid) valid eye samples (need \(CalibrationRunPolicy.minimumTrainingSamplesPerTarget)). Redo."
        case let .fitFailed(reason): "Calibration fit failed (\(reason)). Redo."
        case .geometryChanged: "Viewport, orientation, mode or viewing setup changed. Redo calibration."
        case let .protocolError(reason): "Held-out protocol error (\(reason)). Redo."
        }
    }
}

public enum CalibrationRunPhase: Equatable, Sendable {
    case notStarted
    /// `target` is in view points. `progress` is 0...1 within the current stage.
    case training(index: Int, total: Int, target: ScreenPoint, stage: CalibrationStage, progress: Double)
    case heldOut(pass: Int, step: Int, stepsPerPass: Int, target: HeldOutTarget, point: ScreenPoint,
                 stage: CalibrationStage, progress: Double)
    /// Operator must report whether the marker followed eye-only movement with the head still.
    case awaitingEyeOnlyCheck
    case finished
    case failed(CalibrationRunFailure)
}

/// Drives the P2 protocol from display-link ticks. All times are host-monotonic seconds.
/// Targets are presentation only: they label training samples and score held-out windows and are
/// never used as live inference input.
public struct CalibrationRun {
    public let geometry: RenderGeometry
    public private(set) var phase: CalibrationRunPhase = .notStarted
    public private(set) var calibration: GazeCalibration?
    public private(set) var windowResults: [HeldOutWindowResult] = []
    public private(set) var report: HeldOutReport?
    public private(set) var trainingSampleCounts: [Int] = []

    private var trainingSamples: [CalibrationSample] = []
    private var currentTargetTimestamps = Set<Double>()
    private var stepStartedAt = 0.0
    private var trainingIndex = 0
    private var heldOutPass = 0
    private var heldOutStep = 0
    private var window: HeldOutWindow?
    private var recordedSlots = Set<Int>()

    public init(geometry: RenderGeometry) { self.geometry = geometry }

    public var isComplete: Bool { report?.passesCompleteGate == true }

    public mutating func start(now: Double) {
        self = CalibrationRun(geometry: geometry)
        trainingSampleCounts = Array(repeating: 0, count: CalibrationRunPolicy.trainingTargets.count)
        beginTraining(index: 0, at: now)
    }

    /// Redo always invalidates any previous fit and report.
    public mutating func redo(now: Double) { start(now: now) }

    public mutating func tick(now: Double, observation: GazeObservation?, geometry current: RenderGeometry) {
        guard now.isFinite else { return }
        guard current == geometry else {
            if isRunning || calibration != nil { fail(.geometryChanged) }
            return
        }
        switch phase {
        case .training: tickTraining(now: now, observation: observation)
        case .heldOut: tickHeldOut(now: now, observation: observation)
        default: break
        }
    }

    /// The app lost its measured viewport, changed camera mode or the operator moved the setup.
    public mutating func invalidateForSetupChange() {
        if isRunning || calibration != nil { fail(.geometryChanged) }
    }

    public mutating func recordEyeOnlyResponse(_ response: EyeOnlyResponse) {
        guard phase == .awaitingEyeOnlyCheck else { return }
        do {
            report = try HeldOutReport(windows: windowResults, geometry: geometry, eyeOnlyResponse: response)
            phase = .finished
        } catch {
            fail(.protocolError(String(describing: error)))
        }
    }

    private var isRunning: Bool {
        switch phase {
        case .training, .heldOut, .awaitingEyeOnlyCheck: true
        default: false
        }
    }

    // MARK: Training

    private mutating func beginTraining(index: Int, at now: Double) {
        trainingIndex = index
        stepStartedAt = now
        currentTargetTimestamps.removeAll()
        phase = trainingPhase(stage: .settling, progress: 0)
    }

    private func trainingPhase(stage: CalibrationStage, progress: Double) -> CalibrationRunPhase {
        let targets = CalibrationRunPolicy.trainingTargets
        return .training(index: trainingIndex, total: targets.count,
                         target: viewPoint(targets[trainingIndex]), stage: stage, progress: progress)
    }

    private mutating func tickTraining(now: Double, observation: GazeObservation?) {
        let captureStart = stepStartedAt + CalibrationRunPolicy.settleSeconds
        let captureEnd = captureStart + CalibrationRunPolicy.captureSeconds
        if now < captureStart {
            phase = trainingPhase(stage: .settling, progress: (now - stepStartedAt) / CalibrationRunPolicy.settleSeconds)
            return
        }
        if now < captureEnd {
            collectTrainingSample(observation, now: now, window: captureStart..<captureEnd)
            phase = trainingPhase(stage: .capturing, progress: (now - captureStart) / CalibrationRunPolicy.captureSeconds)
            return
        }
        let count = trainingSampleCounts[trainingIndex]
        guard count >= CalibrationRunPolicy.minimumTrainingSamplesPerTarget else {
            fail(.insufficientTrainingSamples(targetIndex: trainingIndex, validSamples: count))
            return
        }
        if trainingIndex + 1 < CalibrationRunPolicy.trainingTargets.count {
            beginTraining(index: trainingIndex + 1, at: now)
            return
        }
        do {
            calibration = try GazeCalibration.fit(samples: trainingSamples, geometry: geometry)
        } catch {
            fail(.fitFailed(String(describing: error)))
            return
        }
        beginHeldOut(pass: 1, step: 0, at: now)
    }

    private mutating func collectTrainingSample(_ observation: GazeObservation?, now: Double, window: Range<Double>) {
        guard let observation, let features = observation.features,
              window.contains(observation.timestamp),
              GazeQuality.rejectionReason(observation: observation, now: now) == nil,
              currentTargetTimestamps.insert(observation.timestamp).inserted else { return }
        let target = viewPoint(CalibrationRunPolicy.trainingTargets[trainingIndex])
        trainingSamples.append(CalibrationSample(features: features, target: target))
        trainingSampleCounts[trainingIndex] += 1
    }

    // MARK: Held-out

    private mutating func beginHeldOut(pass: Int, step: Int, at now: Double) {
        heldOutPass = pass
        heldOutStep = step
        stepStartedAt = now
        recordedSlots.removeAll()
        let target = CalibrationRunPolicy.heldOutOrder[pass - 1][step]
        do {
            window = try HeldOutWindow(target: target, pass: pass, presentedAt: now, geometry: geometry)
        } catch {
            fail(.protocolError(String(describing: error)))
            return
        }
        phase = heldOutPhase(stage: .settling, progress: 0)
    }

    private func heldOutPhase(stage: CalibrationStage, progress: Double) -> CalibrationRunPhase {
        let order = CalibrationRunPolicy.heldOutOrder[heldOutPass - 1]
        let target = order[heldOutStep]
        return .heldOut(pass: heldOutPass, step: heldOutStep, stepsPerPass: order.count, target: target,
                        point: viewPoint(target.normalized), stage: stage, progress: progress)
    }

    private mutating func tickHeldOut(now: Double, observation: GazeObservation?) {
        guard var current = window, let calibration else { return }
        if now < current.startsAt {
            phase = heldOutPhase(stage: .settling, progress: (now - current.presentedAt) / HeldOutPolicy.settlingSeconds)
            return
        }
        if now < current.endsAt {
            if let slot = scheduledSlot(now: now, startsAt: current.startsAt), recordedSlots.insert(slot).inserted {
                do {
                    try current.record(slot: slot, now: now, observation: observation, calibration: calibration)
                } catch {
                    fail(.protocolError(String(describing: error)))
                    return
                }
                window = current
            }
            phase = heldOutPhase(stage: .capturing, progress: (now - current.startsAt) / HeldOutPolicy.windowSeconds)
            return
        }
        // Slots never sampled (dropped ticks) are counted as missing by `finish()`; no extended windows.
        windowResults.append(current.finish())
        window = nil
        let order = CalibrationRunPolicy.heldOutOrder[heldOutPass - 1]
        if heldOutStep + 1 < order.count {
            beginHeldOut(pass: heldOutPass, step: heldOutStep + 1, at: now)
        } else if heldOutPass < CalibrationRunPolicy.heldOutOrder.count {
            beginHeldOut(pass: heldOutPass + 1, step: 0, at: now)
        } else {
            phase = .awaitingEyeOnlyCheck
        }
    }

    /// The slot whose half-open schedule interval contains `now`, guarding floating-point edges.
    private func scheduledSlot(now: Double, startsAt: Double) -> Int? {
        var slot = Int(((now - startsAt) / HeldOutPolicy.slotSeconds).rounded(.down))
        if slot > 0, now < startsAt + Double(slot) * HeldOutPolicy.slotSeconds { slot -= 1 }
        if now >= startsAt + Double(slot + 1) * HeldOutPolicy.slotSeconds { slot += 1 }
        return (0..<HeldOutPolicy.slots).contains(slot) ? slot : nil
    }

    // MARK: Helpers

    private func viewPoint(_ normalized: ScreenPoint) -> ScreenPoint {
        ScreenPoint(x: normalized.x * geometry.width, y: normalized.y * geometry.height)
    }

    private mutating func fail(_ failure: CalibrationRunFailure) {
        calibration = nil
        report = nil
        window = nil
        phase = .failed(failure)
    }
}
