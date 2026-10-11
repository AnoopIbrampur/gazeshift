import SwiftUI
import Combine
import GazeShiftCore

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
                        diagnostics
                        HStack {
                            Button("Retry") { gaze.invalidate("Not calibrated — capture restarted"); capture.retry() }
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
        .onChange(of: snapshot.sequence) { _, _ in acceptCapture() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { stop() } }
        .onReceive(timer) { _ in
            now = ProcessInfo.processInfo.systemUptime
            gaze.tick(now: now)
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
                CameraView(packet: snapshot.renderPacket, onFailure: capture.rendererFailed)
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
        gaze.invalidate("Not calibrated — camera mode selected")
        capture.start(mode)
    }
    private func stop() {
        gaze.invalidate("Paused — recalibrate after restarting")
        capture.stop()
    }
    private func vector(_ value: SIMD3<Float>) -> String { String(format: "%.3f, %.3f, %.3f", value.x, value.y, value.z) }
    private func blink(_ value: Float?) -> String { value.map { String(format: "%.2f", $0) } ?? "unavailable" }
}
