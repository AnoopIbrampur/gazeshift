import CoreGraphics
import Foundation
import GazeShiftCore
import GazeShiftFlow

/// Converts P1 capture types into the core/flow inputs. One place, one clock:
/// every timestamp handed to the core is the frame's host-monotonic capture estimate.
enum FlowAdapters {
    static func captureTime(_ identity: FrameIdentity) -> Double {
        identity.estimatedCaptureAt ?? identity.receivedAt
    }

    static func frameKey(_ identity: FrameIdentity) -> CaptureFrameKey {
        CaptureFrameKey(generation: identity.generation, frameTimestamp: identity.captureTimestamp)
    }

    /// `nil` eyes still produce an observation so the core records the frame as untracked.
    static func gazeObservation(_ eyes: EyeObservation?, identity: FrameIdentity) -> GazeObservation {
        let features = eyes.flatMap { eyes in
            try? EyeFeatures.from(leftEye: SIMD3<Double>(eyes.leftEyeTranslation),
                                  rightEye: SIMD3<Double>(eyes.rightEyeTranslation),
                                  lookAtPoint: SIMD3<Double>(eyes.lookAtPoint))
        }
        return GazeObservation(timestamp: captureTime(identity), isTracked: eyes?.isTracked ?? false,
                               leftBlink: eyes?.leftBlink.map(Double.init), rightBlink: eyes?.rightBlink.map(Double.init),
                               features: features)
    }

    static func handInput(_ hand: HandObservation) -> NormalizedHandInput {
        NormalizedHandInput(frame: frameKey(hand.identity), captureTime: captureTime(hand.identity),
                            indexTip: ScreenPoint(x: Double(hand.indexTip.x), y: Double(hand.indexTip.y)),
                            thumbTip: ScreenPoint(x: Double(hand.thumbTip.x), y: Double(hand.thumbTip.y)),
                            indexConfidence: Double(hand.indexConfidence), thumbConfidence: Double(hand.thumbConfidence))
    }

    /// `viewingSetupID` names the physical arrangement (distance, stand, lighting). Change it whenever
    /// the setup moves so stale calibrations and regions are rejected by geometry equality.
    static func renderGeometry(viewport: CGSize, scale: CGFloat, mode: CaptureMode,
                               viewingSetupID: String) -> RenderGeometry? {
        try? RenderGeometry(width: Double(viewport.width), height: Double(viewport.height), scale: Double(scale),
                            orientation: .portrait, mode: mode == .setupFront ? .frontSetup : .rearLive,
                            viewingSetupID: viewingSetupID)
    }

    static func cgPoint(_ point: ScreenPoint) -> CGPoint { CGPoint(x: point.x, y: point.y) }

    static func cgRect(_ rect: ScreenRect) -> CGRect { CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height) }
}
