import SwiftUI
import GazeShiftCore
import GazeShiftFlow

/// Owns one air-trace attempt plus the reviewed region and explicit patch offset.
@MainActor
final class AirTraceModel: ObservableObject {
    @Published private(set) var flow: AirTraceFlow?
    @Published private(set) var reviewedRegion: ReviewedRegion?
    /// Explicit user-chosen copy translation in view points. Nil until chosen; no default placement.
    @Published var patchOffset: ScreenPoint?
    static let offsetStep = 20.0

    /// Start in Front setup with a passed front-mode calibration and the stationary reference point.
    func begin(geometry: RenderGeometry, fixation: ScreenPoint, eyeStateDescription: String, generation: UInt64) {
        reviewedRegion = nil
        flow = (try? AirTraceSession(geometry: geometry, fixation: fixation,
                                     eyeStateDescription: eyeStateDescription, captureGeneration: generation))
            .map(AirTraceFlow.init(session:))
    }

    /// Call for every front ARFrame, with that frame's eyes (nil when no face).
    func ingestEyes(_ eyes: EyeObservation?, identity: FrameIdentity, calibration: GazeCalibration?) {
        flow?.recordGaze(frame: FlowAdapters.frameKey(identity),
                         observation: FlowAdapters.gazeObservation(eyes, identity: identity),
                         calibration: calibration, now: ProcessInfo.processInfo.systemUptime)
    }

    /// Call when Vision finishes `identity`'s frame, including when it found no confident hand.
    func ingestHand(_ hand: HandObservation?, identity: FrameIdentity, geometry: RenderGeometry) {
        flow?.handResult(hand.map(FlowAdapters.handInput), frame: FlowAdapters.frameKey(identity),
                         now: ProcessInfo.processInfo.systemUptime, geometry: geometry)
    }

    /// The integrator calls this from the capture watchdog, including while callbacks have stopped.
    func expireInputs(now: Double, geometry: RenderGeometry) {
        flow?.expireInputs(now: now, geometry: geometry)
    }

    func accept() { reviewedRegion = try? flow?.accept() }
    func redo() { reviewedRegion = nil; flow?.redo() }
    func interrupt() { flow?.interrupt() }

    func nudgeOffset(dx: Double, dy: Double) {
        let current = patchOffset ?? ScreenPoint(x: 0, y: 0)
        patchOffset = ScreenPoint(x: current.x + dx, y: current.y + dy)
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

/// Place below/outside the measured preview. Touch reviews and sets offsets; it never traces.
struct AirMapReviewControls: View {
    @ObservedObject var model: AirTraceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(instruction).font(.subheadline)
            Text("Assumed approximation — not a retinal measurement.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Redo") { model.redo() }.buttonStyle(.bordered)
                Button("Accept region") { model.accept() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.flow?.state != .candidateReady)
            }
            HStack(spacing: 6) {
                Text("Copy offset").font(.caption)
                Button("←") { model.nudgeOffset(dx: -AirTraceModel.offsetStep, dy: 0) }
                Button("→") { model.nudgeOffset(dx: AirTraceModel.offsetStep, dy: 0) }
                Button("↑") { model.nudgeOffset(dx: 0, dy: -AirTraceModel.offsetStep) }
                Button("↓") { model.nudgeOffset(dx: 0, dy: AirTraceModel.offsetStep) }
                Text(model.patchOffset.map { String(format: "%+.0f, %+.0f pt", $0.x, $0.y) } ?? "not chosen")
                    .font(.caption.monospaced())
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    private var instruction: String {
        guard let flow = model.flow else { return "Calibrate front mode first, then start air mapping." }
        switch flow.state {
        case .ready: return "Keep looking at the +. Pinch thumb and index, trace one closed outline in the air, return to the start and release."
        case .tracing: return "Tracing — keep your eyes on the +."
        case .candidateReady: return "Review the raw trace (yellow) and bounding ellipse (cyan). Accept or Redo."
        case .accepted: return "Region accepted. Choose the copy offset, then continue to rear calibration."
        case let .invalid(reason): return "Stroke cleared — \(Self.describe(reason)). Redo."
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
