import Combine
import SwiftUI
import GazeShiftCore
import GazeShiftFlow

enum AirMapPolicy {
    /// Stationary fixation reference for the demo: the viewport center.
    static let normalizedFixation = ScreenPoint(x: 0.5, y: 0.5)
    static let eyeStateDescription = "Healthy-user demo · both eyes open · binocular viewing"
    static let offsetStep = 20.0
}

/// Owns one air-trace attempt plus the reviewed region and explicit patch offset.
/// Fed from every published capture snapshot, using `GazeSession`'s geometry and calibration.
@MainActor
final class AirTraceModel: ObservableObject {
    @Published private(set) var flow: AirTraceFlow?
    @Published private(set) var reviewedRegion: ReviewedRegion?
    /// Explicit user-chosen copy translation in view points. Nil until chosen; no default placement.
    @Published var patchOffset: ScreenPoint?
    private var calibration: GazeCalibration?
    private var lastEyeSource = -Double.infinity
    private var lastHandSource = -Double.infinity
    private var subscription: AnyCancellable?

    /// Subscribe once to `CaptureModel.$snapshot` so no snapshot is skipped by view coalescing.
    func attach<P: Publisher>(snapshots: P) where P.Output == CaptureSnapshot, P.Failure == Never {
        guard subscription == nil else { return }
        subscription = snapshots.sink { [weak self] snapshot in
            MainActor.assumeIsolated { self?.receive(snapshot) }
        }
    }

    /// Start in Front setup with the front-mode calibration that passed its held-out report.
    func begin(geometry: RenderGeometry, calibration: GazeCalibration, generation: UInt64) {
        let fixation = ScreenPoint(x: AirMapPolicy.normalizedFixation.x * geometry.width,
                                   y: AirMapPolicy.normalizedFixation.y * geometry.height)
        reviewedRegion = nil
        lastEyeSource = -.infinity
        lastHandSource = -.infinity
        self.calibration = calibration
        flow = (try? AirTraceSession(geometry: geometry, fixation: fixation,
                                     eyeStateDescription: AirMapPolicy.eyeStateDescription,
                                     captureGeneration: generation))
            .map(AirTraceFlow.init(session:))
    }

    /// Leaves air mapping. An accepted region is kept for the rear-mode steps.
    func end() {
        flow = nil
        calibration = nil
    }

    func tick(now: Double, geometry: RenderGeometry?) {
        guard var current = flow else { return }
        let before = current.state
        // Layout, generation or calibration-setup change: an unaccepted stroke must be redone.
        if geometry != current.geometry, before != .accepted { current.interrupt() }
        current.expireStaleHand(now: now)
        if current.state != before { flow = current }
    }

    func accept() {
        guard var current = flow else { return }
        reviewedRegion = try? current.accept()
        flow = current
    }

    func redo() {
        guard var current = flow else { return }
        reviewedRegion = nil
        current.redo()
        flow = current
    }

    /// Mode switch, Stop or Retry. Does nothing once the region is accepted.
    func interrupt() {
        guard var current = flow, current.state != .accepted else { return }
        current.interrupt()
        flow = current
    }

    func nudgeOffset(dx: Double, dy: Double) {
        let current = patchOffset ?? ScreenPoint(x: 0, y: 0)
        patchOffset = ScreenPoint(x: current.x + dx, y: current.y + dy)
    }

    private func receive(_ snapshot: CaptureSnapshot) {
        guard var current = flow, current.state == .ready || current.state == .tracing else { return }
        guard snapshot.mode == .setupFront, snapshot.generation == current.session.captureGeneration else {
            current.interrupt()
            flow = current
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        // Raw eyes (including invalid/blinking ones) so rejections stay truthful; one record per frame.
        if let identity = snapshot.rawEyeIdentity, identity.captureTimestamp > lastEyeSource {
            lastEyeSource = identity.captureTimestamp
            current.recordGaze(frame: FlowAdapters.frameKey(identity),
                               observation: FlowAdapters.gazeObservation(snapshot.rawEyes, identity: identity),
                               calibration: calibration, now: now)
        }
        if let hand = snapshot.hand, hand.identity.captureTimestamp > lastHandSource {
            lastHandSource = hand.identity.captureTimestamp
            current.handResult(FlowAdapters.handInput(hand), frame: FlowAdapters.frameKey(hand.identity),
                               now: now, geometry: current.geometry)
        }
        flow = current
    }
}

/// Drawn inside the measured viewport (same coordinate space as `GazeSession` geometry).
struct AirMapOverlay: View {
    @ObservedObject var model: AirTraceModel

    var body: some View {
        if let flow = model.flow {
            let fixation = FlowAdapters.cgPoint(flow.session.fixation)
            ZStack {
                Path { path in
                    guard let first = flow.rawTrace.first else { return }
                    path.move(to: FlowAdapters.cgPoint(first))
                    for point in flow.rawTrace.dropFirst() { path.addLine(to: FlowAdapters.cgPoint(point)) }
                }
                .stroke(Color.yellow, lineWidth: 1.5)
                if let ellipse = flow.candidateEllipse {
                    let box = CGRect(x: ellipse.center.x - ellipse.radii.x, y: ellipse.center.y - ellipse.radii.y,
                                     width: 2 * ellipse.radii.x, height: 2 * ellipse.radii.y)
                    Path(ellipseIn: box).stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    if let offset = model.patchOffset {
                        Path(box.offsetBy(dx: offset.x, dy: offset.y))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
                Path { path in
                    path.move(to: CGPoint(x: fixation.x - 12, y: fixation.y)); path.addLine(to: CGPoint(x: fixation.x + 12, y: fixation.y))
                    path.move(to: CGPoint(x: fixation.x, y: fixation.y - 12)); path.addLine(to: CGPoint(x: fixation.x, y: fixation.y + 12))
                }
                .stroke(Color.white, lineWidth: 2.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("airMapOverlay")
        }
    }
}

/// ANO-8 controls: explicit Accept/Redo and copy-offset nudges. Touch never draws the region.
struct AirMapControls: View {
    @ObservedObject var model: AirTraceModel
    /// Why air mapping cannot start yet; nil when it can.
    let startBlocker: String?
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AIR MAP").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let flow = model.flow {
                Text(instruction(flow.state)).font(.subheadline)
                Text("Assumed approximation — not a retinal measurement.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Redo") { model.redo() }.buttonStyle(.bordered).accessibilityIdentifier("airMapRedo")
                    Button("Accept region") { model.accept() }
                        .buttonStyle(.borderedProminent)
                        .disabled(flow.state != .candidateReady)
                        .accessibilityIdentifier("airMapAccept")
                    Spacer()
                    Button("Close") { model.end() }.buttonStyle(.bordered)
                }
                if flow.candidate != nil || flow.state == .accepted { offsetControls }
            } else {
                Button("Start air map", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(startBlocker != nil)
                    .accessibilityIdentifier("airMapStart")
                if let startBlocker { Text(startBlocker).font(.caption).foregroundStyle(.secondary) }
                if model.reviewedRegion != nil { Text("Region accepted and kept for live mode.").font(.caption) }
            }
        }
    }

    private var offsetControls: some View {
        HStack(spacing: 6) {
            Text("Copy offset").font(.caption)
            Button("←") { model.nudgeOffset(dx: -AirMapPolicy.offsetStep, dy: 0) }
            Button("→") { model.nudgeOffset(dx: AirMapPolicy.offsetStep, dy: 0) }
            Button("↑") { model.nudgeOffset(dx: 0, dy: -AirMapPolicy.offsetStep) }
            Button("↓") { model.nudgeOffset(dx: 0, dy: AirMapPolicy.offsetStep) }
            Text(model.patchOffset.map { String(format: "%+.0f, %+.0f pt", $0.x, $0.y) } ?? "not chosen")
                .font(.caption.monospaced())
        }
        .buttonStyle(.bordered)
    }

    private func instruction(_ state: AirTraceState) -> String {
        switch state {
        case .ready: "Keep looking at the +. Pinch thumb and index, trace one closed outline in the air, return to the start and release."
        case .tracing: "Tracing — keep your eyes on the +."
        case .candidateReady: "Review the raw trace (yellow) and bounding ellipse (cyan). Accept or Redo."
        case .accepted: "Region accepted. Choose the copy offset, then continue to rear calibration."
        case let .invalid(reason): "Stroke cleared — \(Self.describe(reason)). Redo."
        }
    }

    static func describe(_ reason: AirTraceRejection) -> String {
        switch reason {
        case .fixationDrift: "eyes left the reference"
        case .invalidGaze: "eyes unavailable or blinking"
        case .invalidHand: "fingertips not confidently tracked"
        case .missingPair, .unpairedCapture: "hand or eyes missing for a frame"
        case .stalePair, .captureGap, .duplicateCapture, .invalidTimestamp: "tracking data too old or skipped"
        case .generationChanged, .interrupted, .geometryChanged, .invalidModeTransition: "capture restarted or layout changed"
        case .insufficientSamples: "too few points (need 20)"
        case .degenerateStroke: "outline had no area"
        case .openStroke: "outline did not return to its start"
        case .invalidSetup, .notReadyForReview: "setup not ready"
        }
    }
}
