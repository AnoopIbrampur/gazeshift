import SwiftUI
import Combine
import GazeShiftCore
import GazeShiftFlow

// Progress, controls and reports cannot resize or scroll the measured viewport.
enum ScreenStyle {
    static let background = Color(red: 0.035, green: 0.065, blue: 0.09)
    static let surface = Color(red: 0.065, green: 0.11, blue: 0.14)
    static let accent = Color(red: 0.49, green: 0.91, blue: 0.80)
    static let secondary = Color(red: 0.65, green: 0.73, blue: 0.77)
    static let spacing: CGFloat = 10
    static let pagePadding: CGFloat = 16
    static let cursorDiameter: CGFloat = 18
    static let gazeDiameter: CGFloat = 22
    static let referenceDiameter: CGFloat = 24
    static let minimumViewportHeight: CGFloat = 210
    static let maximumViewportHeight: CGFloat = 360
    static let viewportHeightFraction: CGFloat = 0.43
    static let captureStatusHeight: CGFloat = 38
}

struct ContentView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var capture = CaptureModel()
    @State private var gaze = GazeSession()
    @StateObject private var airTrace = AirTraceModel()
    /// Simulation starts off: normal Live (copy only, never blur).
    @State private var viewMode: ViewMode = .live
    @State private var compositeFailure: String?
    /// Team-approved demo override: use the provisional (failed or untested) calibration for the air map
    /// and simulation, with a persistent warning. Off by default; never counts as validated evidence.
    @State private var unvalidatedDemo = false
    @State private var viewportFrame: CGRect = .zero
    @State private var showReferences = true
    @State private var now = ProcessInfo.processInfo.systemUptime
    private let timer = Timer.publish(every: GazeRunPolicy.schedulerSeconds, on: .main, in: .common).autoconnect()
    private var snapshot: CaptureSnapshot { capture.snapshot }
    private var buildMarker: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "missing"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "missing"
        return "P2-\(version)-\(build)"
    }

    var body: some View {
        GeometryReader { page in
            VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
                header
                Text(captureStatusText)
                    .font(.subheadline.weight(.medium)).foregroundStyle(ScreenStyle.accent)
                    .frame(height: ScreenStyle.captureStatusHeight, alignment: .leading)
                    .accessibilityIdentifier("captureStatus")
                HStack {
                    Button("Front setup") { start(.setupFront) }.accessibilityIdentifier("frontSetup")
                    Button("Rear + eyes") { start(.liveRear) }.accessibilityIdentifier("rearEyes")
                    Spacer()
                }
                .buttonStyle(.borderedProminent).tint(ScreenStyle.surface)
                viewport
                    .frame(height: max(ScreenStyle.minimumViewportHeight, min(ScreenStyle.maximumViewportHeight, page.size.height * ScreenStyle.viewportHeightFraction)))
                HStack {
                    Text("\(Int(viewportFrame.width)) × \(Int(viewportFrame.height)) pt · \(displayScale.formatted())× · portrait")
                    Spacer()
                    Text(snapshot.mode == .setupFront ? "FRONT" : "REAR")
                }
                .font(.caption.monospaced()).foregroundStyle(ScreenStyle.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
                        GazeCalibrationControls(session: $gaze, showReferences: $showReferences, captureReady: snapshot.status == .ready)
                        Divider()
                        unvalidatedDemoToggle
                        AirMapControls(model: airTrace, startBlocker: airMapBlocker, onStart: startAirMap)
                        if airTrace.reviewedRegion != nil { comparisonSection }
                        Divider()
                        diagnostics
                        HStack {
                            Button("Retry") { gaze.invalidate("Not calibrated — capture restarted"); airTrace.interrupt(); capture.retry() }
                                .accessibilityIdentifier("retryCapture")
                            Button("Stop") { stop() }.accessibilityIdentifier("stopCapture")
                            Spacer()
                            Text(buildMarker).font(.caption2.monospaced()).foregroundStyle(ScreenStyle.secondary)
                        }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(ScreenStyle.pagePadding)
        }
        .background(ScreenStyle.background.ignoresSafeArea())
        .onAppear { airTrace.attach(events: capture.events) { gaze } }
        .onChange(of: unvalidatedDemo) { _, on in airTrace.allowUnvalidatedGaze = on }
        .onChange(of: snapshot.sequence) { _, _ in acceptCapture() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { stop() } }
        .onReceive(timer) { _ in
            now = ProcessInfo.processInfo.systemUptime
            gaze.tick(now: now)
            airTrace.tick(now: now, geometry: gaze.geometry)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("GAZESHIFT / P2").font(.caption.weight(.semibold)).foregroundStyle(ScreenStyle.accent)
            Text("Where are your eyes looking?").font(.title3.weight(.semibold))
            Text("Personal calibration · original camera image").font(.caption).foregroundStyle(ScreenStyle.secondary)
        }
    }

    private var captureStatusText: String {
        guard snapshot.status == .ready, !gaze.isRunning, gaze.calibration != nil else { return snapshot.status.text }
        switch gaze.displayState(at: now) {
        case .uncalibrated: return "Not calibrated — original view"
        case .sceneUnavailable: return "Scene unavailable"
        case .unavailable: return "Tracking unavailable — original view"
        case .recovering(let count): return "Tracking recovering (\(count)/\(GazeRunPolicy.recoverySamples)) — original view"
        case .outsideView: return "Gaze outside view — original view"
        case .active: return "Live gaze estimate — original view"
        }
    }

    private var viewport: some View {
        GeometryReader { geometry in
            ZStack {
                ScreenStyle.surface
                CameraView(packet: snapshot.renderPacket, onFailure: capture.rendererFailed,
                           composite: compositeUniforms, onCompositeFailure: { compositeFailure = $0 })
                if snapshot.renderPacket == nil {
                    VStack(spacing: ScreenStyle.spacing) {
                        Image(systemName: "camera").font(.largeTitle)
                        Text(snapshot.status.text).font(.subheadline).multilineTextAlignment(.center)
                    }.padding().foregroundStyle(ScreenStyle.secondary)
                }
                if !gaze.isRunning, snapshot.mode == .setupFront,
                   let hand = snapshot.hand, hand.identity.isFresh(at: now) {
                    Circle().fill(.yellow).frame(width: ScreenStyle.cursorDiameter, height: ScreenStyle.cursorDiameter)
                        .position(x: hand.indexTip.x * geometry.size.width, y: hand.indexTip.y * geometry.size.height)
                    Circle().stroke(.yellow, lineWidth: 2).frame(width: ScreenStyle.cursorDiameter, height: ScreenStyle.cursorDiameter)
                        .position(x: hand.thumbTip.x * geometry.size.width, y: hand.thumbTip.y * geometry.size.height)
                }
                if let measured = gaze.geometry { AirMapOverlay(model: airTrace, geometry: measured) }
                if let composition, compositeFailure == nil { compositionOutline(composition.plan) }
                if unvalidatedDemo {
                    VStack {
                        Text(Self.unvalidatedBanner)
                            .font(.caption2.weight(.bold)).foregroundStyle(.black)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange, in: Capsule())
                            .padding(.top, 6)
                        Spacer()
                    }
                    .accessibilityIdentifier("unvalidatedGazeBanner")
                }
                if showReferences, gaze.calibration != nil, !gaze.isRunning {
                    ForEach(HeldOutTarget.allCases, id: \.rawValue) { reference in
                        RoundedRectangle(cornerRadius: 3).stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(width: ScreenStyle.referenceDiameter, height: ScreenStyle.referenceDiameter)
                            .position(x: reference.normalized.x * geometry.size.width, y: reference.normalized.y * geometry.size.height)
                            .accessibilityLabel("Fixed \(reference.rawValue) reference")
                    }
                }
                if let target = gaze.target {
                    Circle().fill(.white).overlay(Circle().stroke(.black, lineWidth: 3))
                        .frame(width: ScreenStyle.referenceDiameter, height: ScreenStyle.referenceDiameter)
                        .position(x: target.normalized.x * geometry.size.width, y: target.normalized.y * geometry.size.height)
                        .accessibilityLabel(target.label)
                        .task(id: target.id) { gaze.targetPresented(at: ProcessInfo.processInfo.systemUptime, targetID: target.id) }
                }
                if let point = gaze.marker(at: now) {
                    ZStack {
                        Circle().fill(.black.opacity(0.5))
                        Circle().stroke(ScreenStyle.accent, lineWidth: 3)
                        Circle().fill(ScreenStyle.accent).padding(7)
                    }
                    .frame(width: ScreenStyle.gazeDiameter, height: ScreenStyle.gazeDiameter)
                    .position(x: point.x, y: point.y)
                    .accessibilityLabel("Live calibrated gaze estimate")
                    .accessibilityIdentifier("liveGazeMarker")
                }
            }
            .allowsHitTesting(false)
            .clipped()
            .overlay(Rectangle().stroke(ScreenStyle.secondary.opacity(0.3), lineWidth: 1))
            .onAppear { updateLayout(geometry.frame(in: .global)) }
            .onChange(of: geometry.frame(in: .global)) { _, frame in updateLayout(frame) }
            .onChange(of: displayScale) { _, _ in updateLayout(geometry.frame(in: .global)) }
        }
        .accessibilityIdentifier("measuredViewport")
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.support?.text ?? "Support flags unavailable until physical capture starts")
            Text(snapshot.handMessage)
            if let hand = snapshot.hand, hand.identity.isFresh(at: now) {
                Text("Hand t=\(hand.identity.captureTimestamp.formatted(.number.precision(.fractionLength(3)))) · index \(hand.indexConfidence.formatted(.number.precision(.fractionLength(2)))) / thumb \(hand.thumbConfidence.formatted(.number.precision(.fractionLength(2))))")
            }
            if let eyes = snapshot.eyes, let identity = snapshot.eyeIdentity, identity.isFresh(at: now) {
                Text("Raw eyes t=\(identity.captureTimestamp.formatted(.number.precision(.fractionLength(3)))) · transform tracked")
                Text("lookAt (face): \(vector(eyes.lookAtPoint))")
                Text("L eye: \(vector(eyes.leftEyeTranslation)) · R eye: \(vector(eyes.rightEyeTranslation))")
                Text("Blink L/R: \(blink(eyes.leftBlink)) / \(blink(eyes.rightBlink))")
            } else {
                Text("Eyes unavailable · gaze marker hidden")
            }
            Text("lookAtPoint is face-relative; only the personal fit maps it to the display")
        }
        .font(.system(size: 11, design: .monospaced)).foregroundStyle(ScreenStyle.secondary)
        .accessibilityIdentifier("sensorDiagnostics")
    }

    private func updateLayout(_ frame: CGRect) {
        airTrace.layout(frame, scale: displayScale)
        viewportFrame = frame
        capture.layout(frame.size, scale: displayScale)
        gaze.configure(size: frame.size, scale: displayScale, mode: snapshot.mode, generation: snapshot.generation, origin: frame.origin)
    }
    private func acceptCapture() {
        now = ProcessInfo.processInfo.systemUptime
        gaze.configure(size: viewportFrame.size, scale: displayScale, mode: snapshot.mode, generation: snapshot.generation, origin: viewportFrame.origin)
        gaze.receive(snapshot, now: now)
    }
    private func start(_ mode: CaptureMode) {
        if mode == .liveRear { airTrace.prepareForRearSelection() }
        else { airTrace.interrupt() }
        gaze.invalidate("Not calibrated — camera mode selected")
        capture.start(mode)
    }
    private func stop() {
        gaze.invalidate("Paused — recalibrate after restarting")
        airTrace.interrupt()
        capture.stop()
    }
    /// Air mapping needs live Front capture and a front calibration that passed held-out + eye-only (ANO-19).
    private var airMapBlocker: String? {
        guard snapshot.mode == .setupFront else { return "Air map runs in Front setup" }
        guard snapshot.status == .ready else { return "Waiting for live front camera and eyes" }
        guard !gaze.isRunning else { return "Finish the calibration step first" }
        guard gaze.calibration != nil, gaze.geometry != nil else { return "Calibrate first" }
        guard unvalidatedDemo || gaze.report?.passesCompleteGate == true else {
            return "Needs a passed held-out test and eye-only check (or turn on Unvalidated gaze demo)"
        }
        return nil
    }
    // MARK: ANO-10/11 composition

    /// The reviewed region in the current measured geometry, if it may be used here.
    private var currentRegion: ReviewedRegion? {
        guard let geometry = gaze.geometry, let accepted = airTrace.reviewedRegion else { return nil }
        if accepted.displayGeometry == geometry { return accepted }
        return try? accepted.retainedForModeTransition(to: geometry)
    }

    /// Recomputed every frame from calibrated live gaze; nothing adaptive without a passed report.
    private var composition: (plan: CompositionPlan, geometry: RenderGeometry)? {
        guard let geometry = gaze.geometry, airTrace.reviewedRegion != nil else { return nil }
        let sceneHealthy = snapshot.renderPacket?.identity.isFresh(at: now) == true
        let validated = gaze.report?.passesCompleteGate == true
        let allowed = validated || unvalidatedDemo
        let liveGaze = sceneHealthy && allowed ? gaze.marker(at: now) : nil
        // Demo override still uses the MEASURED p90 as the copy safety gap; it is only treated as
        // acceptable because the operator turned the override on. Without a report there is no copy.
        let margin = gaze.report.flatMap { report in
            report.overallErrors.map { LivePlacementMargin(p90ErrorPoints: $0.p90Points, geometry: geometry,
                                                           validated: report.passesCompleteGate || unvalidatedDemo) }
        }
        let plan = CompositionPlanner.plan(mode: viewMode, region: currentRegion, gaze: liveGaze, geometry: geometry,
                                           userOffset: airTrace.patchOffset ?? ScreenPoint(x: .nan, y: .nan),
                                           liveMargin: margin,
                                           cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: geometry.width, height: geometry.height))
        return (plan, geometry)
    }

    /// GPU layers only when something adaptive is drawn and the simulation shader loaded.
    private var compositeUniforms: CompositeUniformValues.GPU? {
        guard compositeFailure == nil, let composition, !composition.plan.isOriginalOnly else { return nil }
        return CompositeUniformValues(plan: composition.plan, geometry: composition.geometry).gpu
    }

    /// Green outline of the simulated blind region; dashed white box where the copy lands.
    @ViewBuilder private func compositionOutline(_ plan: CompositionPlan) -> some View {
        if let blur = plan.blur {
            Ellipse().stroke(Color.green, lineWidth: 3)
                .frame(width: 2 * blur.radii.x, height: 2 * blur.radii.y)
                .position(x: blur.center.x, y: blur.center.y)
                .accessibilityIdentifier("simulatedRegionOutline")
        }
        if let copy = plan.copy {
            Rectangle().stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: copy.destination.width, height: copy.destination.height)
                .position(x: copy.destination.x + copy.destination.width / 2, y: copy.destination.y + copy.destination.height / 2)
                .accessibilityIdentifier("copyDestinationOutline")
        }
    }

    static let unvalidatedBanner = "UNVALIDATED GAZE — accuracy not verified"

    private var unvalidatedDemoToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Unvalidated gaze demo", isOn: $unvalidatedDemo)
                .accessibilityIdentifier("unvalidatedDemoToggle")
            Text(unvalidatedDemo
                 ? "ON: air map and simulation use the provisional calibration even though its accuracy test did not pass. For showing the idea only — not evidence."
                 : "Off: air map and simulation wait for a passed calibration report.")
                .font(.caption).foregroundStyle(unvalidatedDemo ? Color.orange : Color.secondary)
        }
    }

    @ViewBuilder private var comparisonSection: some View {
        Divider()
        if let composition {
            ComparisonControls(mode: $viewMode, plan: composition.plan)
        }
        ForEach(compositionNotes, id: \.self) { note in
            Text(note).font(.caption).foregroundStyle(.orange)
        }
    }

    /// Plain reasons the view stays original, so a missing blur is never silent.
    private var compositionNotes: [String] {
        var notes: [String] = []
        if let compositeFailure { notes.append("Simulation unavailable — \(compositeFailure)") }
        if airTrace.reviewedRegion != nil, gaze.geometry != nil, currentRegion == nil {
            notes.append("Region not usable in this camera mode yet (front→rear carry-over pending, ANO-10)")
        }
        if gaze.report?.passesCompleteGate != true, !unvalidatedDemo {
            notes.append("Effects need a passed calibration report in this mode")
        }
        if unvalidatedDemo, gaze.report?.overallErrors == nil, viewMode != .comparison(.simulatedBlur) {
            notes.append("Copy needs a held-out test result for its safety gap — run Test first")
        }
        if airTrace.patchOffset == nil, viewMode != .comparison(.simulatedBlur), viewMode != .comparison(.original) {
            notes.append("Choose a copy offset in AIR MAP for copy modes")
        }
        return notes
    }

    private func startAirMap() {
        guard airMapBlocker == nil else { return }
        airTrace.begin(gaze: gaze, generation: snapshot.generation)
    }
    private func vector(_ value: SIMD3<Float>) -> String { String(format: "%.3f, %.3f, %.3f", value.x, value.y, value.z) }
    private func blink(_ value: Float?) -> String { value.map { String(format: "%.2f", $0) } ?? "unavailable" }
}
