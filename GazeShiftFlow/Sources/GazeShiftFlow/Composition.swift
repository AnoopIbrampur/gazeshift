import Foundation
import GazeShiftCore

/// The three required demo views. Simulation starts off; normal Live never blurs.
public enum ComparisonMode: String, CaseIterable, Sendable {
    case original, simulatedBlur, simulatedBlurPlusCopy

    public var title: String {
        switch self {
        case .original: "Original"
        case .simulatedBlur: "Simulated blur"
        case .simulatedBlurPlusCopy: "Simulated blur + copy"
        }
    }
}

public enum ViewMode: Equatable, Sendable {
    /// Normal Live assist: relocated copy only, never simulated blur.
    case live
    case comparison(ComparisonMode)
}

/// Copy the `source` rectangle of the ORIGINAL frame to `destination` (same size, view points).
public struct CopyLayer: Equatable, Sendable {
    public let source: ScreenRect
    public let destination: ScreenRect
}

/// Elliptical simulated-blur mask in view points.
public struct BlurLayer: Equatable, Sendable {
    public let center: ScreenPoint
    public let radii: ScreenPoint
}

/// What the renderer draws for one frame. Renderer contract, in this order:
/// 1. sample the original current frame; 2. apply `copy` reading only original pixels;
/// 3. apply `blur` LAST over the composited result. No layer ever samples blurred pixels.
public struct CompositionPlan: Equatable, Sendable {
    public let copy: CopyLayer?
    public let blur: BlurLayer?
    public let statusText: String
    /// Persistent label required whenever a comparison view is selected.
    public let simulationLabel: String?

    public static let simulationLabelText = "Simulated blur — demonstration only"
    public static let trackingUnavailableText = "Tracking unavailable — original view"

    public var isOriginalOnly: Bool { copy == nil && blur == nil }
}

public enum CompositionPlanner {
    /// `gaze` must be nil whenever the shared loss rules say tracking is unavailable or recovering;
    /// then every adaptive layer is removed and the healthy original is shown with a warning.
    public static func plan(mode: ViewMode, region: ReviewedRegion?, gaze: ScreenPoint?,
                            geometry: RenderGeometry, userOffset: ScreenPoint,
                            liveMargin: LivePlacementMargin?, cameraSamplingBounds: ScreenRect?) -> CompositionPlan {
        let label: String? = if case .comparison = mode { CompositionPlan.simulationLabelText } else { nil }
        func originalOnly(_ status: String) -> CompositionPlan {
            CompositionPlan(copy: nil, blur: nil, statusText: status, simulationLabel: label)
        }
        if mode == .comparison(.original) { return originalOnly("Original") }
        guard let region else { return originalOnly("No reviewed region — original view") }
        guard let gaze else { return originalOnly(CompositionPlan.trackingUnavailableText) }

        if mode == .comparison(.simulatedBlur) {
            guard let ellipse = try? region.displayEllipse(gaze: gaze, geometry: geometry) else {
                return originalOnly(CompositionPlan.trackingUnavailableText)
            }
            return CompositionPlan(copy: nil, blur: BlurLayer(center: ellipse.center, radii: ellipse.radii),
                                   statusText: "Simulated blur", simulationLabel: label)
        }

        let result = PlacementPlanner.plan(region: region, gaze: gaze, geometry: geometry, userOffset: userOffset,
                                           liveMargin: liveMargin, cameraSamplingBounds: cameraSamplingBounds)
        guard case let .accepted(placement) = result else {
            let status = result == .rejected(.invalidGaze) ? CompositionPlan.trackingUnavailableText : result.statusText
            return originalOnly(status)
        }
        let copy = CopyLayer(source: placement.source, destination: placement.destination)
        if mode == .live {
            return CompositionPlan(copy: copy, blur: nil, statusText: result.statusText, simulationLabel: nil)
        }
        // Same ellipse that produced the copy, so mask and patch move together with gaze.
        return CompositionPlan(copy: copy, blur: BlurLayer(center: placement.ellipse.center, radii: placement.ellipse.radii),
                               statusText: "Simulated blur + copy", simulationLabel: label)
    }
}

/// Normalized display-UV values (0...1, top-left origin) for the Metal compositor, matching
/// `CameraVertex.displayUV`. Packed to mirror `CompositeUniforms` in CompositeShaders.metal.
public struct CompositeUniformValues: Equatable, Sendable {
    public var copyEnabled: Bool
    public var sourceOrigin: SIMD2<Float>
    public var destinationOrigin: SIMD2<Float>
    public var copySize: SIMD2<Float>
    public var blurEnabled: Bool
    public var blurCenter: SIMD2<Float>
    public var blurRadii: SIMD2<Float>
    /// Blur kernel radius in display UV (provisional visual strength, not a vision model).
    public var blurKernel: SIMD2<Float>

    public static let defaultBlurKernelPoints = 12.0

    public init(plan: CompositionPlan, geometry: RenderGeometry,
                blurKernelPoints: Double = defaultBlurKernelPoints) {
        func uv(_ x: Double, _ y: Double) -> SIMD2<Float> {
            SIMD2(Float(x / geometry.width), Float(y / geometry.height))
        }
        copyEnabled = plan.copy != nil
        sourceOrigin = plan.copy.map { uv($0.source.x, $0.source.y) } ?? .zero
        destinationOrigin = plan.copy.map { uv($0.destination.x, $0.destination.y) } ?? .zero
        copySize = plan.copy.map { uv($0.source.width, $0.source.height) } ?? .zero
        blurEnabled = plan.blur != nil
        blurCenter = plan.blur.map { uv($0.center.x, $0.center.y) } ?? .zero
        blurRadii = plan.blur.map { uv($0.radii.x, $0.radii.y) } ?? .zero
        blurKernel = uv(blurKernelPoints, blurKernelPoints)
    }

    /// Byte layout of `CompositeUniforms` in CompositeShaders.metal: six float2 then two uint (56 bytes).
    public struct GPU: Equatable, Sendable {
        public var sourceOrigin: SIMD2<Float>
        public var destinationOrigin: SIMD2<Float>
        public var copySize: SIMD2<Float>
        public var blurCenter: SIMD2<Float>
        public var blurRadii: SIMD2<Float>
        public var blurKernel: SIMD2<Float>
        public var copyEnabled: UInt32
        public var blurEnabled: UInt32
    }

    public var gpu: GPU {
        GPU(sourceOrigin: sourceOrigin, destinationOrigin: destinationOrigin, copySize: copySize,
            blurCenter: blurCenter, blurRadii: blurRadii, blurKernel: blurKernel,
            copyEnabled: copyEnabled ? 1 : 0, blurEnabled: blurEnabled ? 1 : 0)
    }
}
