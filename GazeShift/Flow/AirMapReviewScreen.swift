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

/// Owns one air-trace attempt and pending reviewed provenance; no rear region is activated here.
@MainActor
final class AirTraceModel: ObservableObject {
    @Published private(set) var flow: AirTraceFlow?
    @Published private(set) var reviewedRegion: ReviewedRegion?
    @Published var patchOffset: ScreenPoint?
    private var subscription: AnyCancellable?
    private var currentGaze: (() -> GazeSession)?
    private var viewportFrame: CGRect?
    private var displayScale: CGFloat?
    private var pendingRearReset = false
    private var retainedInRear = false
    private var regionGeneration: UInt64?

    /// Raw events preserve nil/error inputs and source identity before display filtering.
    func attach<P: Publisher>(events: P, gaze: @escaping () -> GazeSession)
        where P.Output == CaptureEvent, P.Failure == Never {
        guard subscription == nil else { return }
        currentGaze = gaze
        subscription = events.sink { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
    }

    func begin(gaze: GazeSession, generation: UInt64) {
        guard isEligible(gaze), currentGaze.map({ isEligible($0()) }) == true,
              let geometry = gaze.geometry else { return }
        reviewedRegion = nil
        patchOffset = nil
        pendingRearReset = false
        retainedInRear = false
        regionGeneration = generation
        let fixation = ScreenPoint(x: AirMapPolicy.normalizedFixation.x * geometry.width,
                                   y: AirMapPolicy.normalizedFixation.y * geometry.height)
        flow = (try? AirTraceSession(geometry: geometry, fixation: fixation,
                                     eyeStateDescription: AirMapPolicy.eyeStateDescription,
                                     captureGeneration: generation)).map(AirTraceFlow.init(session:))
    }

    /// Closing review retains only its original front provenance, pending a deliberate handoff.
    func end() { flow = nil }

    func layout(_ frame: CGRect, scale: CGFloat) {
        if let viewportFrame, let displayScale, viewportFrame != frame || displayScale != scale { interrupt() }
        viewportFrame = frame
        displayScale = scale
    }

    func tick(now: Double, geometry: RenderGeometry?) {
        if let region = reviewedRegion {
            let old = region.displayGeometry
            let sameDisplay = geometry.map { $0.width == old.width && $0.height == old.height
                && $0.scale == old.scale && $0.orientation == old.orientation
                && $0.viewingSetupID == old.viewingSetupID } == true
            if !sameDisplay || (!pendingRearReset && !retainedInRear && geometry != old) { interrupt() }
        }
        guard validateEligibility(), var current = flow else { return }
        let before = current.state
        current.expireInputs(now: now, geometry: geometry ?? current.geometry)
        if current.state != before { flow = current }
    }

    func accept() {
        guard validateEligibility(), var current = flow else { return }
        reviewedRegion = try? current.accept()
        flow = current
    }

    func redo() {
        guard validateEligibility(), var current = flow else { return }
        reviewedRegion = nil
        patchOffset = nil
        current.redo()
        flow = current
    }

    /// Only the explicit front→rear selection may retain the accepted front provenance.
    /// shortcut: this is pending provenance only; activate a rear region in the later validated P3 handoff.
    func prepareForRearSelection() {
        guard let region = reviewedRegion, let gaze = currentGaze?(), isEligible(gaze),
              gaze.geometry == region.displayGeometry else { interrupt(); return }
        flow = nil
        pendingRearReset = true
    }

    /// The accepted front region, activated for rear composition ONLY after the deliberate front→rear
    /// switch of this session (`retainedInRear`). Core re-checks same size, scale, orientation and
    /// physical setup ID; the rear mode still needs its own fresh calibration before gaze is used.
    func rearRegion(for geometry: RenderGeometry?) -> ReviewedRegion? {
        guard retainedInRear, let region = reviewedRegion, let geometry, geometry.mode == .rearLive else { return nil }
        return try? region.retainedForModeTransition(to: geometry)
    }

    /// Stop, Retry, front restart, capture failure or a physical layout change clears all cached state.
    func interrupt() {
        reviewedRegion = nil
        patchOffset = nil
        pendingRearReset = false
        retainedInRear = false
        regionGeneration = nil
        guard var current = flow else { return }
        current.interrupt()
        flow = current
    }

    func nudgeOffset(dx: Double, dy: Double) {
        let current = patchOffset ?? ScreenPoint(x: 0, y: 0)
        patchOffset = ScreenPoint(x: current.x + dx, y: current.y + dy)
    }

    /// Team-approved "Unvalidated gaze demo": accept the provisional fit instead of a passed report.
    /// Turning it off re-checks immediately, so active strokes and regions fail closed.
    var allowUnvalidatedGaze = false {
        didSet { if oldValue, !allowUnvalidatedGaze { validateEligibility() } }
    }

    private func isEligible(_ gaze: GazeSession) -> Bool {
        !gaze.isRunning && gaze.geometry?.mode == .frontSetup
            && gaze.calibration?.geometry == gaze.geometry && gaze.calibration != nil
            && (gaze.report?.passesCompleteGate == true || allowUnvalidatedGaze)
    }

    @discardableResult
    private func validateEligibility() -> Bool {
        guard let current = flow else {
            if reviewedRegion != nil, !pendingRearReset, !retainedInRear,
               currentGaze.map({ isEligible($0()) }) != true { interrupt() }
            return false
        }
        guard let gaze = currentGaze?(), isEligible(gaze), gaze.geometry == current.geometry else {
            interrupt()
            return false
        }
        return true
    }

    private func receive(_ event: CaptureEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case let .reset(generation, mode):
            guard let prior = flow?.session.captureGeneration ?? regionGeneration, generation > prior else { return }
            if pendingRearReset, mode == .liveRear, reviewedRegion != nil {
                pendingRearReset = false
                retainedInRear = true
                regionGeneration = generation
            } else { interrupt() }
        case let .eyes(eyes, identity, mode):
            guard let current = flow, identity.generation >= current.session.captureGeneration else { return }
            guard identity.generation == current.session.captureGeneration, mode == .setupFront else { interrupt(); return }
            guard validateEligibility(), var current = flow else { return }
            current.recordGaze(frame: FlowAdapters.frameKey(identity),
                               observation: FlowAdapters.gazeObservation(eyes, identity: identity),
                               calibration: currentGaze?().calibration, now: now)
            flow = current
        case let .hand(result, identity, mode):
            guard let current = flow, identity.generation >= current.session.captureGeneration else { return }
            guard identity.generation == current.session.captureGeneration, mode == .setupFront else { interrupt(); return }
            guard validateEligibility(), var current = flow else { return }
            let hand = try? result.get()
            current.handResult(hand.map(FlowAdapters.handInput), frame: FlowAdapters.frameKey(identity),
                               now: now, geometry: current.geometry)
            flow = current
        }
    }
}

/// Render only over the SAME measured preview used by capture and calibration.
/// The caller supplies its current full geometry; a stale trace is never scaled into a new viewport.
struct AirMapOverlay: View {
    @ObservedObject var model: AirTraceModel
    let geometry: RenderGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let flow = model.flow, flow.geometry == geometry { overlay(flow) }
        }
        .frame(width: CGFloat(geometry.width), height: CGFloat(geometry.height), alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityIdentifier("airMapOverlay")
    }

    private func overlay(_ flow: AirTraceFlow) -> some View {
        let fixation = FlowAdapters.cgPoint(flow.session.fixation)
        return ZStack {
            Path { path in
                guard let first = flow.rawTrace.first else { return }
                path.move(to: FlowAdapters.cgPoint(first))
                for point in flow.rawTrace.dropFirst() { path.addLine(to: FlowAdapters.cgPoint(point)) }
            }
            .stroke(Color.yellow, lineWidth: 1.5)
            if let ellipse = flow.candidateEllipse {
                Path(ellipseIn: CGRect(x: ellipse.center.x - ellipse.radii.x, y: ellipse.center.y - ellipse.radii.y,
                                       width: 2 * ellipse.radii.x, height: 2 * ellipse.radii.y))
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                if let offset = model.patchOffset {
                    Path(CGRect(x: ellipse.center.x - ellipse.radii.x + offset.x, y: ellipse.center.y - ellipse.radii.y + offset.y,
                                width: 2 * ellipse.radii.x, height: 2 * ellipse.radii.y))
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
            Path { path in
                path.move(to: CGPoint(x: fixation.x - 10, y: fixation.y)); path.addLine(to: CGPoint(x: fixation.x + 10, y: fixation.y))
                path.move(to: CGPoint(x: fixation.x, y: fixation.y - 10)); path.addLine(to: CGPoint(x: fixation.x, y: fixation.y + 10))
            }
            .stroke(Color.white, lineWidth: 2)
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
                    Button("Redo") { model.redo() }.buttonStyle(.bordered).disabled(startBlocker != nil).accessibilityIdentifier("airMapRedo")
                    Button("Accept region") { model.accept() }
                        .buttonStyle(.borderedProminent)
                        .disabled(startBlocker != nil || flow.state != .candidateReady)
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
                if model.reviewedRegion != nil { Text("Accepted front region pending rear calibration; not active in live mode.").font(.caption) }
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
        case .accepted: "Front region accepted. Choose the offset; rear calibration and handoff remain required."
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
