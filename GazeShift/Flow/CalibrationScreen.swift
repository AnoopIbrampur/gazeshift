import SwiftUI
import GazeShiftCore
import GazeShiftFlow

/// Drives a `CalibrationRun` from a ~120 Hz main-actor loop using the newest capture observation.
@MainActor
final class CalibrationController: ObservableObject {
    @Published private(set) var run: CalibrationRun?
    private var loop: Task<Void, Never>?
    /// Supplied by the integrator: newest eye observation of the current generation (or nil).
    var latestObservation: () -> GazeObservation? = { nil }
    /// Supplied by the integrator: the current measured geometry, nil while layout is invalid.
    var currentGeometry: () -> RenderGeometry? = { nil }

    var calibration: GazeCalibration? { run?.isComplete == true ? run?.calibration : nil }

    func start() {
        guard let geometry = currentGeometry() else { return }
        var next = CalibrationRun(geometry: geometry)
        next.start(now: ProcessInfo.processInfo.systemUptime)
        run = next
        startLoop()
    }

    func redo() { start() }

    func recordEyeOnly(_ response: EyeOnlyResponse) { run?.recordEyeOnlyResponse(response) }

    func invalidate() {
        loop?.cancel()
        run?.invalidateForSetupChange()
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000)
                guard let self, self.tick() else { return }
            }
        }
    }

    /// Returns false once the run no longer needs ticks.
    private func tick() -> Bool {
        guard var current = run else { return false }
        guard let geometry = currentGeometry() else {
            current.invalidateForSetupChange()
            run = current
            return false
        }
        current.tick(now: ProcessInfo.processInfo.systemUptime, observation: latestObservation(), geometry: geometry)
        run = current
        switch current.phase {
        case .training, .heldOut: return true
        default: return false
        }
    }
}

/// Target presentation and results. Place it over the SAME measured viewport used for capture.
struct CalibrationScreen: View {
    @ObservedObject var controller: CalibrationController
    var onAccept: () -> Void = {}

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
            switch controller.run?.phase ?? .notStarted {
            case .notStarted:
                prompt("Hold the phone still at your usual distance. Look at each dot until it moves.",
                       button: "Start calibration") { controller.start() }
            case let .training(index, total, target, stage, progress):
                targetView(at: target, stage: stage, progress: progress)
                caption("Calibration \(index + 1) of \(total)")
            case let .heldOut(pass, step, steps, target, point, stage, progress):
                targetView(at: point, stage: stage, progress: progress)
                caption("Check pass \(pass) · \(step + 1) of \(steps)\(target == .centerControl ? " · center control" : "")")
            case .awaitingEyeOnlyCheck:
                eyeOnlyCheck
            case .finished:
                results
            case let .failed(failure):
                prompt(failure.text, button: "Redo calibration") { controller.redo() }
            }
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier("calibrationScreen")
    }

    private func targetView(at point: ScreenPoint, stage: CalibrationStage, progress: Double) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 3).frame(width: 34, height: 34)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(stage == .capturing ? Color.green : Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 34, height: 34)
            Circle().fill(.white).frame(width: 8, height: 8)
        }
        .position(FlowAdapters.cgPoint(point))
    }

    private func caption(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.caption.monospaced()).padding(8).background(.black.opacity(0.6), in: Capsule())
        }
        .padding(.bottom, 8)
    }

    private func prompt(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Text(text).multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var eyeOnlyCheck: some View {
        VStack(spacing: 12) {
            Text("Eye-only check").font(.headline)
            Text("Keep the head still and move only the eyes. Did the gaze marker follow the eyes?")
                .multilineTextAlignment(.center).font(.subheadline)
            HStack {
                Button("Yes — followed") { controller.recordEyeOnly(.observedPass) }.buttonStyle(.borderedProminent)
                Button("No") { controller.recordEyeOnly(.observedFail) }.buttonStyle(.bordered)
            }
            Text("Operator-observed; record it in the evidence log.").font(.caption2).opacity(0.7)
        }
        .padding()
    }

    @ViewBuilder private var results: some View {
        if let run = controller.run, let report = run.report {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.passesCompleteGate ? "Calibration PASSED" : "Calibration FAILED")
                        .font(.headline).foregroundStyle(report.passesCompleteGate ? .green : .red)
                    Text("Numerical gate \(flag(report.passesNumericalGate)) · protocol \(flag(report.passesProtocolGate)) · eye-only \(eyeOnly(report.eyeOnlyResponse))")
                    Text("Novel coverage \(percent(report.overallValidFraction)) · unique samples \(report.overallReceivedUniqueSamples) · rejected slots \(report.overallRejectedSlots)")
                    if let errors = report.overallErrors {
                        Text("Median \(points(errors.medianPoints)) (\(percent(errors.medianDiagonalFraction)) diag) · p90 \(points(errors.p90Points)) (\(percent(errors.p90DiagonalFraction)) diag)")
                    }
                    Divider().overlay(.white.opacity(0.3))
                    ForEach(Array((report.novelWindows + report.centerControls).enumerated()), id: \.offset) { _, window in
                        Text(windowLine(window)).foregroundStyle(window.passesNumericalGate ? Color.white : Color.orange)
                    }
                    Text("Training samples per target: \(run.trainingSampleCounts.map(String.init).joined(separator: " "))")
                        .opacity(0.7)
                    HStack {
                        Button("Redo") { controller.redo() }.buttonStyle(.bordered)
                        if report.passesCompleteGate { Button("Use calibration", action: onAccept).buttonStyle(.borderedProminent) }
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding()
            }
        }
    }

    private func windowLine(_ window: HeldOutWindowResult) -> String {
        let rejections = window.rejectionCounts.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: ",")
        let error = window.errors.map { "med \(points($0.medianPoints)) p90 \(points($0.p90Points))" } ?? "no valid"
        return "P\(window.pass) \(window.target.rawValue): \(window.validPredictions)/\(window.expectedSlots) · uniq \(window.receivedUniqueSamples) · \(error)\(rejections.isEmpty ? "" : " · \(rejections)")"
    }

    private func flag(_ value: Bool) -> String { value ? "pass" : "FAIL" }
    private func eyeOnly(_ value: EyeOnlyResponse) -> String {
        switch value {
        case .notTested: "not tested"
        case .observedPass: "pass"
        case .observedFail: "FAIL"
        }
    }
    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
    private func points(_ value: Double) -> String { String(format: "%.0fpt", value) }
}
