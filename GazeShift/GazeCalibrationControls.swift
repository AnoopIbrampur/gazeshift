import SwiftUI
import GazeShiftCore

private struct GazeReportDocument: Identifiable {
    let id = UUID()
    let text: String
}

struct GazeCalibrationControls: View {
    @Binding var session: GazeSession
    @Binding var showReferences: Bool
    let captureReady: Bool
    @State private var document: GazeReportDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
            Text(stateTitle).font(.headline).accessibilityIdentifier("gazeState")
            Text(session.target?.label ?? session.message)
                .font(.subheadline)
                .accessibilityIdentifier("gazeProgress")
            if session.isRunning {
                Text("Fixate the white dot. 0.5s settle + 1s sample; keep head and distance still.")
                    .font(.caption).foregroundStyle(ScreenStyle.secondary)
                if session.phase == .calibrating {
                    Text("Valid samples this target: \(session.currentTrainingCount)")
                        .font(.caption.monospaced())
                    Text(session.message).font(.caption).foregroundStyle(ScreenStyle.secondary)
                }
                Button("Cancel run") { session.cancel() }.accessibilityIdentifier("cancelGazeRun")
            } else {
                HStack {
                    Button(session.calibration == nil ? "Calibrate" : "Recalibrate") { session.startCalibration() }
                        .disabled(!captureReady)
                        .accessibilityIdentifier("calibrateGaze")
                    Button("Test accuracy") { session.startEvaluation() }
                        .disabled(session.calibration == nil || !captureReady)
                        .accessibilityIdentifier("evaluateGaze")
                }
                if session.calibration != nil {
                    Toggle("Reference boxes", isOn: $showReferences).accessibilityIdentifier("referenceTargets")
                    Text("White boxes: fixed references · mint dot: live gaze estimate. A missing dot means tracking is unavailable, recovering, or outside the view.")
                        .font(.caption).foregroundStyle(ScreenStyle.secondary)
                }
                if let report = session.report {
                    Text(report.passesNumericalGate ? "Timed accuracy criteria passed" : "Timed accuracy criteria not passed")
                        .font(.subheadline.weight(.semibold))
                    Text("Keep head still; look left, right, up and down. Did the dot respond to your eyes?")
                        .font(.caption)
                    HStack {
                        Button("Eyes moved dot") { session.recordEyeOnly(.observedPass) }
                            .accessibilityIdentifier("eyeOnlyPass")
                        Button("Did not respond") { session.recordEyeOnly(.observedFail) }
                            .accessibilityIdentifier("eyeOnlyFail")
                    }
                    Text(eyeOnlyLabel(report.eyeOnlyResponse)).font(.caption).foregroundStyle(ScreenStyle.secondary)
                    Button("View / share test report") { document = GazeReportDocument(text: session.reportText) }
                        .accessibilityIdentifier("gazeReport")
                }
            }
            Text("Portrait · stable seated distance. Recalibrate after moving the phone or changing distance. Experimental screen estimate; no vision benefit established.")
                .font(.caption).foregroundStyle(ScreenStyle.secondary)
        }
        .buttonStyle(.bordered)
        .tint(ScreenStyle.accent)
        .sheet(item: $document) { item in
            NavigationStack {
                ScrollView { Text(item.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                    .navigationTitle("Gaze test report")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: item.text) } }
            }
        }
    }

    private var stateTitle: String {
        switch session.phase {
        case .uncalibrated: "Not calibrated"
        case .calibrating: "Calibrating this camera mode"
        case .provisional: "Provisional calibration"
        case .evaluating: "Timed held-out test"
        case .evaluated: session.report?.passesCompleteGate == true ? "Evaluated · engineering gate passed" : "Evaluated · complete gate not passed"
        case .failed: "Calibration / test unavailable"
        }
    }

    private func eyeOnlyLabel(_ response: EyeOnlyResponse) -> String {
        switch response {
        case .notTested: "Eye-only response: not tested"
        case .observedPass: "Eye-only response: user-reported pass"
        case .observedFail: "Eye-only response: user-reported fail"
        }
    }
}

extension GazeSession {
    var reportText: String {
        guard let report, let geometry else { return "No held-out report available" }
        var lines = [
            "GazeShift experimental display-gaze test",
            "Mode: \(geometry.mode.rawValue); portrait; viewport \(geometry.width) × \(geometry.height) pt; scale \(geometry.scale)",
            "Setup: \(geometry.viewingSetupID)",
            "Viewing distance/head stability: requested, not measured automatically",
            "Training samples by target (9 required): \(trainingCounts)",
            "Features: face-relative eye-midpoint → lookAtPoint direction ratios → personal affine fit → view points",
            "Normalized view = points / viewport; drawing pixels = points × scale. Camera-image UV transform is separate.",
            "Timing: host monotonic capture estimates; UI target acknowledgement; no measured photon latency",
            "Each window: 0.5s settle + exactly 1s; 20 slots / 50ms. Late/missing slots are rejected, never extended.",
            "Gate: each novel window ≥80% valid and ≥10 distinct predictions; median ≤10%, p90 ≤20% diagonal, overall and per window; timed interleaved center controls plus eye-only pass.",
            "Numerical: \(report.passesNumericalGate ? "PASS" : "NOT PASSED"); protocol: \(report.passesProtocolGate ? "PASS" : "NOT PASSED"); complete: \(report.passesCompleteGate ? "PASS" : "NOT PASSED")",
            "Eye-only response (entered by user): \(eyeOnlyText(report.eyeOnlyResponse))",
            "Novel total: received \(report.overallReceivedUniqueSamples), valid \(report.overallValidPredictions)/160, rejected \(report.overallRejectedSlots); \(statistics(report.overallErrors))",
            "Novel rejections: \(rejections(report.overallRejectionCounts))",
            "Center controls are reported separately and excluded from novel accuracy:",
        ]
        for result in completedWindows {
            lines.append("pass \(result.pass) \(result.target.rawValue): received \(result.receivedUniqueSamples), valid \(result.validPredictions)/\(result.expectedSlots), rejected \(result.rejectedSlots); \(statistics(result.errors)); \(rejections(result.rejectionCounts))")
            lines.append("  presented \(timestamp(result.presentedAt)); capture window [\(timestamp(result.startsAt)), \(timestamp(result.endsAt))) host seconds")
        }
        lines.append("Finite offscreen predictions remain in accuracy scores; the live dot rejects them. Missing features (including a failed finite-feature conversion) are missingQuality. Raw unavailable camera samples are missing.")
        lines.append("Computed from app inputs; this report does not prove physical eye-only movement, clinical retinal mapping, patient benefit, or a playable device demonstration.")
        return lines.joined(separator: "\n")
    }

    private func statistics(_ errors: ErrorStatistics?) -> String {
        guard let errors else { return "errors unavailable" }
        return String(format: "median %.1fpt (%.1f%%), p90 %.1fpt (%.1f%% diagonal)",
                      errors.medianPoints, errors.medianDiagonalFraction * 100,
                      errors.p90Points, errors.p90DiagonalFraction * 100)
    }
    private func rejections(_ counts: [RejectionReason: Int]) -> String {
        counts.isEmpty ? "none" : counts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: ", ")
    }
    private func timestamp(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "unavailable" }
    private func eyeOnlyText(_ value: EyeOnlyResponse) -> String {
        switch value { case .notTested: "not tested"; case .observedPass: "user-reported pass"; case .observedFail: "user-reported fail" }
    }
}
