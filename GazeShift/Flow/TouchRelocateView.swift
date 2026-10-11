import SwiftUI
import GazeShiftCore
import GazeShiftFlow

/// Backup demo, no eye tracking: on the live rear view, circle what you can't see with a finger;
/// a copy of that area appears at a rule-of-thirds spot and can be dragged anywhere. The circled
/// spot is optionally blurred to simulate the blind area.
struct TouchRelocateView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var capture = CaptureModel()
    @State private var viewportSize: CGSize = .zero
    @State private var touch: TouchRelocation?
    @State private var dragStart: ScreenPoint?
    @State private var blurSource = true
    @State private var compositeFailure: String?
    private var snapshot: CaptureSnapshot { capture.snapshot.forDisplay() }

    var body: some View {
        GeometryReader { page in
            VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GAZESHIFT / TOUCH RELOCATE").font(.caption.weight(.semibold)).foregroundStyle(ScreenStyle.accent)
                    Text("Circle what you can't see").font(.title3.weight(.semibold))
                    Text("Eye tracking off · draw with your finger, then drag the copy.")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                Text(snapshot.status.text).font(.subheadline.weight(.medium)).foregroundStyle(ScreenStyle.accent)
                    .frame(height: ScreenStyle.captureStatusHeight, alignment: .leading)
                HStack {
                    Button("Rear camera") { capture.start(.liveRear) }.accessibilityIdentifier("touchRear")
                    Button("Front camera") { capture.start(.setupFront) }
                    Spacer()
                }.buttonStyle(.borderedProminent).tint(ScreenStyle.surface)
                viewport.frame(height: max(ScreenStyle.minimumViewportHeight,
                    min(ScreenStyle.maximumViewportHeight, page.size.height * ScreenStyle.viewportHeightFraction)))
                controls
            }.padding(ScreenStyle.pagePadding)
        }
        .background(ScreenStyle.background.ignoresSafeArea())
        .onAppear { capture.start(.liveRear) }
        .onDisappear { capture.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { capture.stop() } }
    }

    private var viewport: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ScreenStyle.surface
                CameraView(packet: snapshot.renderPacket, onFailure: capture.rendererFailed,
                           composite: compositeFailure == nil ? touch?.uniforms(blurSource: blurSource) : nil,
                           onCompositeFailure: { compositeFailure = $0 })
                    .allowsHitTesting(false)
                overlays
            }
            .contentShape(Rectangle())
            .gesture(drawGesture)
            .clipped()
            .overlay(Rectangle().stroke(ScreenStyle.secondary.opacity(0.3), lineWidth: 1))
            .onAppear { updateLayout(geometry.size) }
            .onChange(of: geometry.size) { _, size in updateLayout(size) }
        }
        .accessibilityIdentifier("touchViewport")
    }

    @ViewBuilder private var overlays: some View {
        if let touch {
            if touch.isDrawing {
                Path { path in
                    guard let first = touch.stroke.first else { return }
                    path.move(to: cg(first))
                    for point in touch.stroke.dropFirst() { path.addLine(to: cg(point)) }
                }
                .stroke(Color.yellow, lineWidth: 2)
                .allowsHitTesting(false)
            }
            if let source = touch.source {
                Ellipse().stroke(Color.green, lineWidth: 3)
                    .frame(width: source.width, height: source.height)
                    .position(x: source.x + source.width / 2, y: source.y + source.height / 2)
                    .allowsHitTesting(false)
            }
            if let destination = touch.destination {
                Rectangle().stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.white.opacity(0.001))
                    .frame(width: destination.width, height: destination.height)
                    .position(x: destination.x + destination.width / 2, y: destination.y + destination.height / 2)
                    .gesture(moveGesture)
                    .accessibilityIdentifier("touchCopy")
            }
        }
    }

    /// Draw a closed shape anywhere outside the copy; a new stroke replaces the previous region.
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard viewportSize.width > 0 else { return }
                var current = touch ?? TouchRelocation(viewWidth: viewportSize.width, viewHeight: viewportSize.height)
                let point = ScreenPoint(x: value.location.x, y: value.location.y)
                if current.isDrawing { current.add(point) } else { current.begin(at: point) }
                touch = current
            }
            .onEnded { _ in
                guard var current = touch, current.isDrawing else { return }
                current.finish()
                touch = current
            }
    }

    /// Hold and drag the copy; it stays fully inside the view.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard var current = touch, let destination = current.destination else { return }
                let start = dragStart ?? ScreenPoint(x: destination.x, y: destination.y)
                dragStart = start
                current.moveDestination(to: ScreenPoint(x: start.x + value.translation.width,
                                                        y: start.y + value.translation.height))
                touch = current
            }
            .onEnded { _ in dragStart = nil }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(instruction).font(.subheadline)
            Toggle("Blur the circled spot (simulated blind area)", isOn: $blurSource)
            HStack {
                Button("Clear") { touch = nil }.buttonStyle(.bordered)
                Button("Stop") { capture.stop() }.buttonStyle(.bordered)
                Button("Retry camera") { capture.retry() }.buttonStyle(.bordered)
            }
            Text(CompositionPlan.simulationLabelText).font(.caption.weight(.semibold)).foregroundStyle(.orange)
            Text("The copy duplicates the original camera pixels and covers what is under it. Not a medical device or simulation of any person's vision.")
                .font(.caption2).foregroundStyle(ScreenStyle.secondary)
            if let compositeFailure {
                Text("Copy/blur unavailable — \(compositeFailure)").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var instruction: String {
        guard let touch else { return "Draw a circle around something with your finger." }
        if touch.isDrawing { return "Drawing… lift your finger to finish." }
        if touch.source == nil { return "Too small — draw a bigger circle." }
        return "Drag the dashed copy to where you can see it. Draw again to pick a new spot."
    }

    private func updateLayout(_ size: CGSize) {
        guard size != viewportSize else { return }
        viewportSize = size
        touch = nil
        capture.layout(size, scale: displayScale)
    }

    private func cg(_ point: ScreenPoint) -> CGPoint { CGPoint(x: point.x, y: point.y) }
}

/// Root switcher so the touch backup never edits the air-trace screen.
struct DemoRootView: View {
    enum Screen: String, CaseIterable { case airTrace = "Air trace", touch = "Touch" }
    @State private var screen: Screen = .touch

    var body: some View {
        VStack(spacing: 0) {
            Picker("Demo", selection: $screen) {
                ForEach(Screen.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, ScreenStyle.pagePadding).padding(.top, 4)
            // Only one screen (and so one AR session) exists at a time.
            switch screen {
            case .airTrace: ContentView()
            case .touch: TouchRelocateView()
            }
        }
        .background(ScreenStyle.background.ignoresSafeArea())
    }
}
