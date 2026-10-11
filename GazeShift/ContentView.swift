import SwiftUI
import Combine
import GazeShiftCore
import GazeShiftFlow

// Progress, controls and reports cannot resize or scroll the measured viewport.
enum ScreenStyle {
    static let background = Color.white
    static let surface = Color(red: 245.0 / 255, green: 245.0 / 255, blue: 247.0 / 255)
    static let accent = Color(red: 0, green: 102.0 / 255, blue: 204.0 / 255)
    static let ink = Color(red: 29.0 / 255, green: 29.0 / 255, blue: 31.0 / 255)
    static let secondary = Color(red: 110.0 / 255, green: 110.0 / 255, blue: 115.0 / 255)
    static let spacing: CGFloat = 8
    static let minimumControlHeight: CGFloat = 44
    static let pagePadding: CGFloat = 16
    static let cursorDiameter: CGFloat = 18
    static let gazeDiameter: CGFloat = 22
    static let referenceDiameter: CGFloat = 24
    static let minimumViewportHeight: CGFloat = 210
    static let maximumViewportHeight: CGFloat = 360
    static let viewportHeightFraction: CGFloat = 0.43
    static let cameraAspectRatio: CGFloat = 3.0 / 4.0
    static let captureStatusHeight: CGFloat = 38
    static let gazeControlsAnchor = "gazeControls"
}

// Dormant eye-driven screen retained; no gaze session/calibration is instantiated in the manual build.
#if false
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
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
                            GazeCalibrationControls(session: $gaze, showReferences: $showReferences, captureReady: snapshot.status == .ready)
                                .id(ScreenStyle.gazeControlsAnchor)
                            Divider()
                            unvalidatedDemoToggle
                            blurChecklist
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
                    .onChange(of: gaze.isRunning) { _, isRunning in
                        if isRunning { scroll.scrollTo(ScreenStyle.gazeControlsAnchor, anchor: .top) }
                    }
                }
            }
            .padding(ScreenStyle.pagePadding)
        }
        .background(ScreenStyle.background.ignoresSafeArea())
        .onAppear { airTrace.attach(events: capture.events) { gaze } }
        .onChange(of: unvalidatedDemo) { _, on in airTrace.allowUnvalidatedGaze = on }
        // Demo: jump straight to the blur once a region is accepted, so nothing is hidden behind toggles.
        .onChange(of: airTrace.reviewedRegion != nil) { _, accepted in
            if accepted, unvalidatedDemo { viewMode = .comparison(.simulatedBlur) }
        }
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
        return airTrace.rearRegion(for: geometry)
    }

    /// Recomputed every frame from calibrated live gaze; nothing adaptive without a passed report.
    private var composition: (plan: CompositionPlan, geometry: RenderGeometry)? {
        guard let geometry = gaze.geometry, airTrace.reviewedRegion != nil else { return nil }
        let sceneHealthy = snapshot.renderPacket?.identity.isFresh(at: now) == true
        let validated = gaze.report?.passesCompleteGate == true
        let allowed = validated || unvalidatedDemo
        let liveGaze = sceneHealthy && allowed ? demoAwareMarker : nil
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

    /// On-screen diagnosis of every gate between "camera on" and "blur drawn", in pipeline order.
    private var blurChecklist: some View {
        let marker = demoAwareMarker
        let plan = composition?.plan
        let rows: [(Bool, String)] = [
            (snapshot.status == .ready, "Capture ready — \(snapshot.mode == .setupFront ? "FRONT" : "REAR"): \(snapshot.status.text)"),
            (snapshot.renderPacket?.identity.isFresh(at: now) == true, "Scene fresh"),
            (gaze.calibration != nil, "Calibration fitted (phase: \(gaze.phase))"),
            (gaze.report?.passesCompleteGate == true || unvalidatedDemo,
             unvalidatedDemo ? "Accuracy gate bypassed (demo ON)" : "Accuracy gate passed (or turn on demo)"),
            (airTrace.flow != nil || airTrace.reviewedRegion != nil, "Air map: \(airTrace.flow.map { "\($0.state)" } ?? "not started")"),
            (airTrace.reviewedRegion != nil, "Region accepted"),
            (currentRegion != nil, "Region usable in this camera mode"),
            (marker != nil, "Live gaze dot: \(gazeStateText)"),
            (viewMode == .comparison(.simulatedBlur) || viewMode == .comparison(.simulatedBlurPlusCopy),
             "View mode: \(viewModeText)"),
            (plan?.blur != nil, "Blur layer planned: \(plan?.statusText ?? "no plan")"),
            (compositeFailure == nil, compositeFailure.map { "Shader: \($0)" } ?? "Blur shader loaded"),
            (compositeUniforms?.blurEnabled == 1, "Blur sent to renderer"),
        ]
        return VStack(alignment: .leading, spacing: 2) {
            Text("BLUR CHECKLIST").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text("\(row.0 ? "✅" : "❌") \(row.1)").foregroundStyle(row.0 ? Color.secondary : Color.orange)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .accessibilityIdentifier("blurChecklist")
    }

    /// Validated path uses the strict marker; the opt-in demo falls back to the edge-pinned estimate.
    private var demoAwareMarker: ScreenPoint? {
        if let strict = gaze.marker(at: now) { return strict }
        return unvalidatedDemo ? gaze.clampedDemoMarker(at: now) : nil
    }

    private var gazeStateText: String {
        switch gaze.displayState(at: now) {
        case .uncalibrated: "uncalibrated"
        case .sceneUnavailable: "scene unavailable"
        case .unavailable: "eyes unavailable/blinking"
        case let .recovering(n): "recovering \(n)/\(GazeRunPolicy.recoverySamples)"
        case .outsideView: unvalidatedDemo ? "outside view — demo pins it to the edge" : "OUTSIDE the camera view (calibration off)"
        case .active: "active"
        }
    }

    private var viewModeText: String {
        switch viewMode {
        case .live: "Live (no blur — turn on Demo comparison)"
        case let .comparison(mode): mode.title
        }
    }

    static let unvalidatedBanner = "UNVALIDATED GAZE — accuracy not verified"

    private var unvalidatedDemoToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Unvalidated gaze demo", isOn: $unvalidatedDemo)
                .accessibilityIdentifier("unvalidatedDemoToggle")
            Text(unvalidatedDemo
                 ? "ON: air map and simulation use the provisional calibration even though its accuracy test did not pass. While tracing, eyes must stay open and tracked but their exact position is NOT checked. For showing the idea only — not evidence."
                 : "Off: air map and simulation wait for a passed calibration report. Turning the demo off clears regions accepted without a passed front report; draw those again in Front setup.")
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
            notes.append("Region not available here — accept it in Front setup, then press Rear + eyes without moving the layout")
        }
        if gaze.report?.passesCompleteGate != true, !unvalidatedDemo {
            notes.append("Effects need a passed calibration report in this mode")
        }
        if unvalidatedDemo, gaze.report?.overallErrors == nil, viewMode != .comparison(.simulatedBlur) {
            notes.append("Copy needs a held-out test result for its safety gap — run Test first")
        }
        if snapshot.mode == .liveRear {
            notes.append("Hand tracking is front-camera only — trace in Front setup, then press Rear + eyes")
        }
        if gaze.calibration == nil {
            notes.append("Calibrate in this camera mode — the blur follows the calibrated gaze")
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

#endif

struct ContentView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var capture = CaptureModel()
    @StateObject private var airTrace = AirTraceModel()
    @State private var viewMode: ViewMode = .live
    @State private var compositeFailure: String?
    @State private var viewportFrame: CGRect = .zero
    @State private var now = ProcessInfo.processInfo.systemUptime
    @State private var showingInfo = false
    private let timer = Timer.publish(every: CaptureLimits.watchdogInterval, on: .main, in: .common).autoconnect()
    private var snapshot: CaptureSnapshot { capture.snapshot.forDisplay() }
    private var geometry: RenderGeometry? {
        try? RenderGeometry(width: Double(viewportFrame.width), height: Double(viewportFrame.height),
                            scale: Double(displayScale), orientation: .portrait,
                            mode: snapshot.mode == .setupFront ? .frontSetup : .rearLive,
                            viewingSetupID: "viewport-origin-\(viewportFrame.origin.x)-\(viewportFrame.origin.y)")
    }

    var body: some View {
        GeometryReader { page in
            VStack(spacing: 0) {
                header
                viewport
                    .frame(width: page.size.width, height: page.size.width / ScreenStyle.cameraAspectRatio)
                    .overlay(alignment: .topLeading) { cameraStatus }
                    .overlay(alignment: .bottomLeading) {
                        if viewMode != .live {
                            Text("Simulation · demo only")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, ScreenStyle.spacing)
                                .background(.black.opacity(0.7), in: Capsule())
                                .padding(ScreenStyle.pagePadding)
                                .accessibilityIdentifier("simulationLabel")
                        }
                    }
                ScrollView {
                    VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
                        cameraSelection
                        AirMapControls(model: airTrace, startBlocker: airMapBlocker,
                                       cameraMode: snapshot.mode, onStart: startAirMap)
                        if airTrace.reviewedRegion != nil, let composition {
                            Divider()
                            ComparisonControls(mode: $viewMode, plan: composition.plan)
                        }
                        if let compositeFailure {
                            Text("Effect unavailable — \(compositeFailure)")
                                .font(.subheadline).foregroundStyle(.red)
                                .accessibilityIdentifier("compositeFailure")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ScreenStyle.pagePadding)
                }
                .background(ScreenStyle.surface)
            }
        }
        .background(ScreenStyle.background.ignoresSafeArea())
        .foregroundStyle(ScreenStyle.ink)
        .tint(ScreenStyle.accent)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showingInfo) { infoScreen }
        .onAppear { airTrace.attach(events: capture.events) }
        .onChange(of: airTrace.reviewedRegion != nil) { _, accepted in
            if accepted { viewMode = .comparison(.simulatedBlur) }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { stop() } }
        .onReceive(timer) { _ in
            now = ProcessInfo.processInfo.systemUptime
            airTrace.tick(now: now, geometry: geometry)
        }
    }

    private var header: some View {
        HStack {
            Text("GazeShift").font(.title3.weight(.semibold))
            Spacer()
            Button { showingInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: ScreenStyle.minimumControlHeight, height: ScreenStyle.minimumControlHeight)
            }
            .accessibilityLabel("About GazeShift and camera controls")
            .accessibilityIdentifier("showInfo")
        }
        .padding(.leading, ScreenStyle.pagePadding)
        .padding(.trailing, ScreenStyle.spacing)
        .frame(height: ScreenStyle.minimumControlHeight)
        .background(ScreenStyle.background)
    }

    private var cameraStatus: some View {
        Text(snapshot.status == .ready && snapshot.renderPacket != nil
             ? (snapshot.mode == .setupFront ? "Front · Live" : "Rear · Live")
             : (snapshot.status == .simulator ? "Camera unavailable in Simulator" : snapshot.status.text))
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScreenStyle.pagePadding).padding(.vertical, ScreenStyle.spacing)
            .background(.black.opacity(0.65))
            .accessibilityIdentifier("captureStatus")
    }

    private var cameraSelection: some View {
        HStack(spacing: ScreenStyle.spacing) {
            cameraButton("Front", mode: .setupFront, identifier: "frontSetup")
            cameraButton("Rear", mode: .liveRear, identifier: "rearScene")
        }
    }

    private func cameraButton(_ title: String, mode: CaptureMode, identifier: String) -> some View {
        Button { start(mode) } label: {
            Text(title).font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: ScreenStyle.minimumControlHeight)
                .foregroundStyle(snapshot.mode == mode ? .white : ScreenStyle.accent)
                .background(snapshot.mode == mode ? ScreenStyle.accent : ScreenStyle.background, in: Capsule())
                .overlay(Capsule().stroke(ScreenStyle.accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start \(title.lowercased()) camera")
        .accessibilityAddTraits(snapshot.mode == mode ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var infoScreen: some View {
        NavigationStack {
            List {
                Section("How to use") {
                    Text("Front → Start drawing. Trace a loop; keep your index visible while your other hand taps Finish shape.")
                    Text("Review → Accept region → Adjust copy → Rear.")
                    Text("Simulation: Original, Blur or Blur + Copy. Off shows the copy without blur.")
                }
                Section("About this demo") {
                    Text("Screen-fixed approximation · no eye tracking")
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("eyeTrackingDisabledBanner")
                    Text("The region stays on screen. It cannot track a retinal blind spot or measure damage.")
                    Text("Blur is an illustration. Copy duplicates pixels and covers destination content. Patient benefit is unproven.")
                }
                Section("Camera & diagnostics") {
                    LabeledContent("Camera", value: snapshot.mode == .setupFront ? "Front" : "Rear")
                    Text(snapshot.status.text)
                    Text(snapshot.handMessage)
                    if let hand = snapshot.hand {
                        LabeledContent("Index confidence", value: hand.indexConfidence.formatted(.number.precision(.fractionLength(2))))
                    }
                    Text(snapshot.support?.text ?? "Support is checked when the camera starts.")
                    LabeledContent("Viewport", value: "\(Int(viewportFrame.width)) × \(Int(viewportFrame.height)) pt")
                    LabeledContent("Display", value: "\(displayScale.formatted())× · portrait")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
                }
                .font(.subheadline)
                .accessibilityIdentifier("sensorDiagnostics")
                Section {
                    Button("Retry camera") { airTrace.interrupt(); capture.retry() }
                        .frame(minHeight: ScreenStyle.minimumControlHeight)
                        .accessibilityIdentifier("retryCapture")
                    Button("Stop camera") { stop() }
                        .frame(minHeight: ScreenStyle.minimumControlHeight)
                        .accessibilityIdentifier("stopCapture")
                }
            }
            .navigationTitle("About GazeShift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingInfo = false }
                        .frame(minHeight: ScreenStyle.minimumControlHeight)
                        .accessibilityIdentifier("dismissInfo")
                }
            }
        }
        .tint(ScreenStyle.accent)
        .preferredColorScheme(.light)
    }

    private var viewport: some View {
        GeometryReader { measured in
            ZStack {
                Color.black
                CameraView(packet: snapshot.renderPacket, onFailure: capture.rendererFailed,
                           composite: compositeUniforms, onCompositeFailure: { compositeFailure = $0 })
                if snapshot.renderPacket == nil {
                    Image(systemName: "camera").font(.system(size: 40, weight: .regular)).foregroundStyle(.white.opacity(0.55))
                }
                if snapshot.mode == .setupFront, let hand = snapshot.hand {
                    Circle().fill(.yellow).frame(width: ScreenStyle.cursorDiameter, height: ScreenStyle.cursorDiameter)
                        .position(x: hand.indexTip.x * measured.size.width, y: hand.indexTip.y * measured.size.height)
                }
                if let geometry { AirMapOverlay(model: airTrace, geometry: geometry) }
                if let composition, compositeFailure == nil { compositionOutline(composition.plan) }
            }
            .allowsHitTesting(false).clipped()
            .onAppear { updateLayout(measured.frame(in: .global)) }
            .onChange(of: measured.frame(in: .global)) { _, frame in updateLayout(frame) }
            .onChange(of: displayScale) { _, _ in updateLayout(measured.frame(in: .global)) }
        }.accessibilityIdentifier("measuredViewport")
    }

    private var currentRegion: ReviewedRegion? {
        guard let geometry, let region = airTrace.reviewedRegion else { return nil }
        return region.displayGeometry == geometry ? region : airTrace.rearRegion(for: geometry)
    }

    private var composition: (plan: CompositionPlan, geometry: RenderGeometry)? {
        guard let geometry, airTrace.reviewedRegion != nil else { return nil }
        let plan = CompositionPlanner.planScreenFixed(mode: viewMode, region: currentRegion,
            sourceAvailable: snapshot.renderPacket != nil, geometry: geometry,
            userOffset: airTrace.patchOffset ?? ScreenPoint(x: .nan, y: .nan),
            cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: geometry.width, height: geometry.height))
        return (plan, geometry)
    }

    private var compositeUniforms: CompositeUniformValues.GPU? {
        guard compositeFailure == nil, let composition, !composition.plan.isOriginalOnly else { return nil }
        return CompositeUniformValues(plan: composition.plan, geometry: composition.geometry).gpu
    }

    @ViewBuilder private func compositionOutline(_ plan: CompositionPlan) -> some View {
        if let blur = plan.blur {
            Ellipse().stroke(.green, lineWidth: 3)
                .frame(width: 2 * blur.radii.x, height: 2 * blur.radii.y)
                .position(x: blur.center.x, y: blur.center.y)
                .accessibilityIdentifier("simulatedRegionOutline")
        }
        if let copy = plan.copy {
            Rectangle().stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: copy.destination.width, height: copy.destination.height)
                .position(x: copy.destination.x + copy.destination.width / 2, y: copy.destination.y + copy.destination.height / 2)
                .accessibilityIdentifier("copyDestinationOutline")
        }
    }

    private var airMapBlocker: String? {
        guard snapshot.mode == .setupFront else { return "Select Front to draw a region." }
        guard snapshot.status == .ready, snapshot.renderPacket != nil else { return "Start Front to draw a region." }
        guard geometry != nil else { return "Preparing the camera view…" }
        guard let hand = snapshot.hand, hand.identity.generation == snapshot.generation,
              hand.identity.isFresh(at: ProcessInfo.processInfo.systemUptime),
              hand.indexConfidence.isFinite,
              (CaptureLimits.minimumHandJointConfidence...1).contains(hand.indexConfidence),
              hand.indexTip.x.isFinite, hand.indexTip.y.isFinite,
              (0...1).contains(hand.indexTip.x), (0...1).contains(hand.indexTip.y) else {
            return "Show your index finger to start drawing."
        }
        return nil
    }

    private func updateLayout(_ frame: CGRect) {
        airTrace.layout(frame, scale: displayScale)
        viewportFrame = frame
        capture.layout(frame.size, scale: displayScale)
    }

    private func startAirMap() {
        guard airMapBlocker == nil, let geometry else { return }
        airTrace.begin(geometry: geometry, generation: snapshot.generation)
    }

    private func start(_ mode: CaptureMode) {
        if mode == .liveRear { airTrace.prepareForRearSelection(geometry: geometry) }
        else { airTrace.interrupt() }
        capture.start(mode)
    }

    private func stop() { airTrace.interrupt(); capture.stop() }
}
