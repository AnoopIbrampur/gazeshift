import Combine
import SwiftUI
import GazeShiftCore
import GazeShiftFlow

enum AirMapPolicy {
    /// Stationary fixation reference for the demo: the viewport center.
    static let normalizedFixation = ScreenPoint(x: 0.5, y: 0.5)
    static let eyeStateDescription = "Eye tracking disabled · screen-fixed approximation"
    static let offsetStep = 20.0
    // A thicker raw line and a start dot make closure visible over a busy camera scene.
    static let traceLineWidth = 3.0
    static let startDotDiameter = 10.0
}

// Dormant eye-driven adapter retained for a future separately validated experiment.
#if false
/// Owns one air-trace attempt and the reviewed provenance for a deliberate same-display rear handoff.
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
    private var regionRequiresUnvalidatedGaze = false

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
        regionRequiresUnvalidatedGaze = false
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
        regionRequiresUnvalidatedGaze = reviewedRegion != nil && currentGaze?().report?.passesCompleteGate != true
        flow = current
    }

    func redo() {
        guard validateEligibility(), var current = flow else { return }
        reviewedRegion = nil
        patchOffset = nil
        regionRequiresUnvalidatedGaze = false
        current.redo()
        flow = current
    }

    /// Only the explicit front→rear selection may retain the accepted front provenance.
    /// The original front provenance stays pending until the rear capture reset completes.
    func prepareForRearSelection() {
        guard let region = reviewedRegion, let gaze = currentGaze?(), isEligible(gaze),
              gaze.geometry == region.displayGeometry else { interrupt(); return }
        // Approval can be revoked after acceptance while the demo keeps front eligibility alive.
        // Carry that current dependency into rear mode before its new calibration clears the report.
        regionRequiresUnvalidatedGaze = regionRequiresUnvalidatedGaze || gaze.report?.passesCompleteGate != true
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
        regionRequiresUnvalidatedGaze = false
        guard var current = flow else { return }
        current.interrupt()
        flow = current
    }

    func nudgeOffset(dx: Double, dy: Double) {
        let current = patchOffset ?? ScreenPoint(x: 0, y: 0)
        patchOffset = ScreenPoint(x: current.x + dx, y: current.y + dy)
    }

    /// Team-approved "Unvalidated gaze demo": accept the provisional fit instead of a passed report.
    /// Leaving the demo clears dependent provenance even in pending/retained rear state: a region
    /// accepted with a failed front report must not become validated by a later passed rear report.
    var allowUnvalidatedGaze = false {
        didSet {
            if oldValue, !allowUnvalidatedGaze {
                if regionRequiresUnvalidatedGaze { interrupt() }
                else { validateEligibility() }
            }
        }
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
                               calibration: currentGaze?().calibration, now: now,
                               ignoreGazePosition: allowUnvalidatedGaze)
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

#endif

/// Hand-only outline and deliberate same-display front→rear region handoff.
@MainActor
final class AirTraceModel: ObservableObject {
    @Published private(set) var flow: AirTraceFlow?
    @Published private(set) var reviewedRegion: ReviewedRegion?
    @Published var patchOffset: ScreenPoint?
    private var subscription: AnyCancellable?
    private var viewportFrame: CGRect?
    private var displayScale: CGFloat?
    private var pendingRearReset = false
    private var retainedInRear = false
    private var regionGeneration: UInt64?

    func attach<P: Publisher>(events: P) where P.Output == CaptureEvent, P.Failure == Never {
        guard subscription == nil else { return }
        subscription = events.sink { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
    }

    func begin(geometry: RenderGeometry, generation: UInt64, now: Double = ProcessInfo.processInfo.systemUptime) {
        guard geometry.mode == .frontSetup else { return }
        if let state = flow?.state, state == .armed || state == .tracing || state == .candidateReady { return }
        interrupt()
        regionGeneration = generation
        guard let session = try? AirTraceSession(indexOnlyGeometry: geometry, captureGeneration: generation) else { return }
        var current = AirTraceFlow(session: session)
        current.startDrawing(at: now, geometry: geometry)
        flow = current
    }

    func finish() {
        guard var current = flow else { return }
        current.finishDrawing(now: ProcessInfo.processInfo.systemUptime, geometry: current.geometry)
        flow = current
    }

    func end() { flow = nil }

    func layout(_ frame: CGRect, scale: CGFloat) {
        if let viewportFrame, let displayScale, viewportFrame != frame || displayScale != scale { interrupt() }
        viewportFrame = frame
        displayScale = scale
    }

    func tick(now: Double, geometry: RenderGeometry?) {
        if let region = reviewedRegion, let geometry {
            let deliberateTransition = (pendingRearReset || retainedInRear)
                && (try? region.retainedForModeTransition(to: geometry)) != nil
            if region.displayGeometry != geometry, !deliberateTransition { interrupt() }
        } else if reviewedRegion != nil { interrupt() }
        guard var current = flow else { return }
        let before = current.state
        current.expireInputs(now: now, geometry: geometry ?? current.geometry)
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
        patchOffset = nil
        current.redo()
        flow = current
    }

    func prepareForRearSelection(geometry: RenderGeometry?) {
        guard let region = reviewedRegion, geometry == region.displayGeometry,
              geometry?.mode == .frontSetup else { interrupt(); return }
        flow = nil
        pendingRearReset = true
    }

    func rearRegion(for geometry: RenderGeometry?) -> ReviewedRegion? {
        guard retainedInRear, let region = reviewedRegion, let geometry else { return nil }
        return try? region.retainedForModeTransition(to: geometry)
    }

    func interrupt() {
        reviewedRegion = nil
        patchOffset = nil
        pendingRearReset = false
        retainedInRear = false
        regionGeneration = nil
        if var current = flow { current.interrupt(); flow = current }
    }

    func nudgeOffset(dx: Double, dy: Double) {
        let current = patchOffset ?? ScreenPoint(x: 0, y: 0)
        patchOffset = ScreenPoint(x: current.x + dx, y: current.y + dy)
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
        case .eyes:
            break // Eye tracking is disabled; dormant eye events cannot affect the manual experiment.
        case let .source(identity, mode):
            guard var current = currentFlow(identity: identity, mode: mode) else { return }
            current.recordSource(frame: FlowAdapters.frameKey(identity), captureTime: FlowAdapters.captureTime(identity),
                                 now: now, geometry: current.geometry)
            flow = current
        case let .hand(result, identity, mode):
            guard var current = currentFlow(identity: identity, mode: mode) else { return }
            current.indexResult((try? result.get()).map(FlowAdapters.indexInput), frame: FlowAdapters.frameKey(identity),
                                captureTime: FlowAdapters.captureTime(identity), now: now, geometry: current.geometry)
            flow = current
        }
    }

    private func currentFlow(identity: FrameIdentity, mode: CaptureMode) -> AirTraceFlow? {
        guard let current = flow, identity.generation >= current.session.captureGeneration else { return nil }
        guard identity.generation == current.session.captureGeneration, mode == .setupFront else { interrupt(); return nil }
        return current
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
        return ZStack {
            Path { path in
                guard let first = flow.rawTrace.first else { return }
                path.move(to: FlowAdapters.cgPoint(first))
                for point in flow.rawTrace.dropFirst() { path.addLine(to: FlowAdapters.cgPoint(point)) }
            }
            .stroke(Color.yellow, lineWidth: AirMapPolicy.traceLineWidth)
            if let first = flow.rawTrace.first {
                Circle().stroke(.yellow, lineWidth: AirMapPolicy.traceLineWidth)
                    .frame(width: AirMapPolicy.startDotDiameter, height: AirMapPolicy.startDotDiameter)
                    .position(FlowAdapters.cgPoint(first))
            }
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
        }
    }
}


/// Explicit drawing/review actions; touch controls never draw the region.
struct AirMapControls: View {
    @ObservedObject var model: AirTraceModel
    let startBlocker: String?
    let cameraMode: CaptureMode
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
            if model.reviewedRegion != nil {
                Text(cameraMode == .setupFront
                     ? "Region ready. Adjust the copy, then select Rear."
                     : "Region ready. Adjust the copy to compare.")
                    .font(.subheadline).foregroundStyle(ScreenStyle.secondary)
                offsetControls
                if cameraMode == .setupFront { redrawButton }
            } else if let flow = model.flow {
                Text(instruction(flow.state)).font(.subheadline)
                HStack(spacing: ScreenStyle.spacing) {
                    switch flow.state {
                    case .armed, .tracing:
                        Button("Finish shape") { model.finish() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("airMapFinish")
                    case .candidateReady:
                        Button("Accept region") { model.accept() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("airMapAccept")
                        redrawButton
                    default:
                        redrawButton
                    }
                    Spacer(minLength: 0)
                    Button("Cancel") { model.end() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("airMapCancel")
                }
                .controlSize(.large).buttonBorderShape(.capsule)
                if flow.candidate != nil { offsetControls }
            } else {
                Text(startBlocker ?? "Trace a closed loop with your index finger.")
                    .font(.subheadline).foregroundStyle(ScreenStyle.secondary)
                Button(action: onStart) {
                    Text("Start drawing").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
                .disabled(startBlocker != nil)
                .accessibilityIdentifier("airMapStart")
            }
        }
    }

    private var redrawButton: some View {
        Button("Redraw") { model.end(); onStart() }
            .buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
            .disabled(startBlocker != nil)
            .accessibilityIdentifier("airMapRedo")
    }

    private var offsetControls: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
                HStack(spacing: ScreenStyle.spacing) {
                    offsetButton("arrow.left", label: "Move copy left", dx: -AirMapPolicy.offsetStep, dy: 0)
                    offsetButton("arrow.right", label: "Move copy right", dx: AirMapPolicy.offsetStep, dy: 0)
                    offsetButton("arrow.up", label: "Move copy up", dx: 0, dy: -AirMapPolicy.offsetStep)
                    offsetButton("arrow.down", label: "Move copy down", dx: 0, dy: AirMapPolicy.offsetStep)
                }
                Text(model.patchOffset.map { String(format: "%+.0f, %+.0f pt", $0.x, $0.y) } ?? "Choose a direction to place the copy.")
                    .font(.caption.monospaced()).foregroundStyle(ScreenStyle.secondary)
            }
            .padding(.bottom, ScreenStyle.spacing)
        } label: {
            Text("Adjust copy").font(.body.weight(.semibold))
                .frame(minHeight: ScreenStyle.minimumControlHeight)
        }
        .accessibilityIdentifier("copyAdjustment")
    }

    private func offsetButton(_ symbol: String, label: String, dx: Double, dy: Double) -> some View {
        Button { model.nudgeOffset(dx: dx, dy: dy) } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: ScreenStyle.minimumControlHeight)
                .background(ScreenStyle.background, in: RoundedRectangle(cornerRadius: ScreenStyle.spacing))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func instruction(_ state: AirTraceState) -> String {
        switch state {
        case .ready: "Show your index finger to start drawing."
        case .armed: "Move your index finger to begin the outline."
        case .tracing: "Close the loop. Keep your finger visible while tapping Finish."
        case .candidateReady: "Review the yellow outline and cyan ellipse."
        case .accepted: "Region ready. Adjust the copy, then select Rear."
        case let .invalid(reason): "Stroke cleared: \(Self.describe(reason)). Redraw to try again."
        }
    }

    static func describe(_ reason: AirTraceRejection) -> String {
        switch reason {
        case .fixationDrift: "eyes left the reference"
        case .invalidGaze: "eyes unavailable or blinking"
        case .invalidHand: "index finger not confidently tracked"
        case .missingPair, .unpairedCapture: "hand or source frame missing"
        case .stalePair, .captureGap, .duplicateCapture, .invalidTimestamp: "tracking data too old or skipped"
        case .generationChanged, .interrupted, .geometryChanged, .invalidModeTransition: "capture restarted or layout changed"
        case .insufficientSamples: "too few points (need 20)"
        case .degenerateStroke: "outline had no area"
        case .openStroke: "outline did not return to its start"
        case .invalidSetup, .notReadyForReview: "setup not ready"
        }
    }
}
