import SwiftUI

private enum ScreenStyle {
    static let background = Color(red: 0.035, green: 0.065, blue: 0.09)
    static let surface = Color(red: 0.065, green: 0.11, blue: 0.14)
    static let accent = Color(red: 0.49, green: 0.91, blue: 0.80)
    static let secondary = Color(red: 0.65, green: 0.73, blue: 0.77)
    static let spacing: CGFloat = 12
    static let pagePadding: CGFloat = 20
    static let cursorDiameter: CGFloat = 18
    static let minimumViewportHeight: CGFloat = 210
    static let statusHeight: CGFloat = 40
    static let diagnosticsHeight: CGFloat = 126
}

struct ContentView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var capture = CaptureModel()
    @State private var viewportSize: CGSize = .zero
    private var snapshot: CaptureSnapshot { capture.snapshot }
    private var buildMarker: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "missing"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "missing"
        return "P1-\(version)-\(build)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GAZESHIFT / P1").font(.caption.weight(.semibold)).foregroundStyle(ScreenStyle.accent)
                Text("Live inputs, original view.").font(.title2.weight(.semibold))
                Text("Experimental sensor check · no calibrated gaze yet").font(.caption).foregroundStyle(ScreenStyle.secondary)
            }
            Text(snapshot.status.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ScreenStyle.accent)
                .frame(height: ScreenStyle.statusHeight, alignment: .leading)
                .accessibilityIdentifier("captureStatus")
            HStack(spacing: 8) {
                Button("Front setup") { capture.start(.setupFront) }.accessibilityIdentifier("frontSetup")
                Button("Rear + eyes") { capture.start(.liveRear) }.accessibilityIdentifier("rearEyes")
            }
            .buttonStyle(.borderedProminent)
            .tint(ScreenStyle.surface)
            viewport
            HStack {
                Text("\(Int(viewportSize.width)) × \(Int(viewportSize.height)) pt · \(displayScale.formatted())× · portrait")
                Spacer()
                Text(snapshot.mode == .setupFront ? "FRONT" : "REAR")
            }
            .font(.caption.monospaced()).foregroundStyle(ScreenStyle.secondary)
            diagnostics
            HStack {
                Button("Retry") { capture.retry() }.accessibilityIdentifier("retryCapture")
                Button("Stop") { capture.stop() }.accessibilityIdentifier("stopCapture")
                Spacer()
                Text(buildMarker).font(.caption2.monospaced()).foregroundStyle(ScreenStyle.secondary)
            }
            .buttonStyle(.bordered)
        }
        .padding(ScreenStyle.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScreenStyle.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in if phase == .background { capture.stop() } }
    }

    private var viewport: some View {
        GeometryReader { geometry in
            ZStack {
                ScreenStyle.surface
                CameraView(packet: snapshot.renderPacket, onFailure: capture.rendererFailed)
                if snapshot.renderPacket == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "camera").font(.largeTitle)
                        Text(snapshot.status.text).font(.subheadline).multilineTextAlignment(.center)
                    }
                    .padding().foregroundStyle(ScreenStyle.secondary)
                }
                if let hand = snapshot.hand, hand.identity.isFresh(at: ProcessInfo.processInfo.systemUptime) {
                    Circle().fill(ScreenStyle.accent).frame(width: ScreenStyle.cursorDiameter, height: ScreenStyle.cursorDiameter)
                        .position(x: hand.indexTip.x * geometry.size.width, y: hand.indexTip.y * geometry.size.height)
                    Circle().stroke(.yellow, lineWidth: 2).frame(width: ScreenStyle.cursorDiameter, height: ScreenStyle.cursorDiameter)
                        .position(x: hand.thumbTip.x * geometry.size.width, y: hand.thumbTip.y * geometry.size.height)
                }
            }
            .clipped()
            .overlay(Rectangle().stroke(ScreenStyle.secondary.opacity(0.3), lineWidth: 1))
            .onAppear { updateLayout(geometry.size) }
            .onChange(of: geometry.size) { _, size in updateLayout(size) }
            .onChange(of: displayScale) { _, _ in updateLayout(geometry.size) }
        }
        .frame(minHeight: ScreenStyle.minimumViewportHeight)
        .accessibilityIdentifier("measuredViewport")
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.support?.text ?? "Support flags unavailable until physical capture starts")
            Text(snapshot.handMessage)
            if let hand = snapshot.hand, hand.identity.isFresh(at: ProcessInfo.processInfo.systemUptime) {
                Text("Hand t=\(hand.identity.captureTimestamp.formatted(.number.precision(.fractionLength(3)))) · index \(hand.indexConfidence.formatted(.number.precision(.fractionLength(2)))) / thumb \(hand.thumbConfidence.formatted(.number.precision(.fractionLength(2))))")
            }
            if let eyes = snapshot.eyes, let identity = snapshot.eyeIdentity, identity.isFresh(at: ProcessInfo.processInfo.systemUptime) {
                Text("Raw eyes t=\(identity.captureTimestamp.formatted(.number.precision(.fractionLength(3)))) · transform tracked")
                Text("lookAt (face): \(vector(eyes.lookAtPoint))")
                Text("L eye: \(vector(eyes.leftEyeTranslation)) · R eye: \(vector(eyes.rightEyeTranslation))")
                Text("Blink L/R: \(blink(eyes.leftBlink)) / \(blink(eyes.rightBlink))")
            } else {
                Text("Eyes unavailable · no gaze marker")
                Text("lookAtPoint is face-relative, not screen coordinates")
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(ScreenStyle.secondary)
        .lineLimit(1)
        .frame(height: ScreenStyle.diagnosticsHeight, alignment: .topLeading)
        .accessibilityIdentifier("sensorDiagnostics")
    }

    private func updateLayout(_ size: CGSize) {
        viewportSize = size
        capture.layout(size, scale: displayScale)
    }
    private func vector(_ value: SIMD3<Float>) -> String {
        String(format: "%.3f, %.3f, %.3f", value.x, value.y, value.z)
    }
    private func blink(_ value: Float?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "unavailable"
    }
}
