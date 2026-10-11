import Foundation

/// An axis-aligned rectangle in canonical full-viewport view points, never raw camera pixels.
public struct ScreenRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
/// The caller supplies measured final-mode p90 error after the required validation gates pass.
public struct LivePlacementMargin: Sendable {
    public let p90ErrorPoints: Double
    public let geometry: RenderGeometry
    public let validated: Bool
    public init(p90ErrorPoints: Double, geometry: RenderGeometry, validated: Bool) {
        self.p90ErrorPoints = p90ErrorPoints; self.geometry = geometry; self.validated = validated
    }
}
public enum PlacementRejection: String, Equatable, Sendable {
    case invalidGaze, invalidOffset, unvalidatedLiveMargin, regionGeometryChanged
    case invalidSamplingBounds, sourceOutsideBounds, destinationOutsideBounds, destinationOverlapsRegion
}
public enum CopySamplingSource: Equatable, Sendable { case originalFrame }
public struct PatchPlacement: Equatable, Sendable {
    public let ellipse: DisplayEllipse
    public let source: ScreenRect
    public let destination: ScreenRect
    public let safetyGapPoints: Double
    public let samplingSource: CopySamplingSource = .originalFrame
}
public enum PlacementResult: Equatable, Sendable {
    case accepted(PatchPlacement)
    case rejected(PlacementRejection)
    public var statusText: String {
        switch self {
        case .accepted: "Relocated view"
        case .rejected: "No valid placement — original view"
        }
    }
}
public enum PlacementDefaults {
    // One measured p90 error is a provisional engineering gap, not a clinical usable-vision claim.
    public static let liveP90SafetyGapMultiplier = 1.0
    // Zero extra engineering clearance for a fixed display region; bounds and overlap still reject.
    public static let screenFixedSafetyGapPoints = 0.0
}

public enum PlacementPlanner {
    /// The renderer must sample `source` from the original current frame before any copy or blur.
    /// `cameraSamplingBounds` is the valid camera image extent mapped into the same display coordinates.
    /// The caller separately gates live gaze/source freshness; this planner has no captured frame input.
    public static func plan(region: ReviewedRegion, gaze: ScreenPoint?, geometry: RenderGeometry,
                            userOffset: ScreenPoint, liveMargin: LivePlacementMargin?,
                            cameraSamplingBounds: ScreenRect?) -> PlacementResult {
        guard let gaze, geometry.contains(gaze) else { return .rejected(.invalidGaze) }
        guard userOffset.x.isFinite, userOffset.y.isFinite else { return .rejected(.invalidOffset) }
        guard let liveMargin, liveMargin.validated, liveMargin.geometry == geometry,
              liveMargin.p90ErrorPoints.isFinite, liveMargin.p90ErrorPoints >= 0 else {
            return .rejected(.unvalidatedLiveMargin)
        }
        guard let cameraSamplingBounds, validRectangle(cameraSamplingBounds) else { return .rejected(.invalidSamplingBounds) }
        guard let ellipse = try? region.displayEllipse(gaze: gaze, geometry: geometry) else { return .rejected(.regionGeometryChanged) }
        return plan(ellipse: ellipse, geometry: geometry, userOffset: userOffset,
                    gap: liveMargin.p90ErrorPoints * PlacementDefaults.liveP90SafetyGapMultiplier,
                    cameraSamplingBounds: cameraSamplingBounds)
    }

    /// Display-fixed regions have no tracking-error margin; overlap and bounds checks still apply.
    public static func planScreenFixed(region: ReviewedRegion, geometry: RenderGeometry,
                                       userOffset: ScreenPoint, cameraSamplingBounds: ScreenRect?) -> PlacementResult {
        guard userOffset.x.isFinite, userOffset.y.isFinite else { return .rejected(.invalidOffset) }
        guard let cameraSamplingBounds, validRectangle(cameraSamplingBounds) else { return .rejected(.invalidSamplingBounds) }
        guard let ellipse = try? region.screenFixedEllipse(geometry: geometry) else { return .rejected(.regionGeometryChanged) }
        return plan(ellipse: ellipse, geometry: geometry, userOffset: userOffset, gap: PlacementDefaults.screenFixedSafetyGapPoints,
                    cameraSamplingBounds: cameraSamplingBounds)
    }

    private static func plan(ellipse: DisplayEllipse, geometry: RenderGeometry, userOffset: ScreenPoint,
                             gap: Double, cameraSamplingBounds: ScreenRect) -> PlacementResult {
        let source = ScreenRect(x: ellipse.center.x - ellipse.radii.x,
                                y: ellipse.center.y - ellipse.radii.y,
                                width: 2 * ellipse.radii.x, height: 2 * ellipse.radii.y)
        let destination = ScreenRect(x: source.x + userOffset.x, y: source.y + userOffset.y,
                                     width: source.width, height: source.height)
        let viewport = ScreenRect(x: 0, y: 0, width: geometry.width, height: geometry.height)
        guard contains(viewport, source), contains(cameraSamplingBounds, source) else { return .rejected(.sourceOutsideBounds) }
        guard contains(viewport, destination), contains(cameraSamplingBounds, destination) else { return .rejected(.destinationOutsideBounds) }
        // Conservative simplification: use the ellipse's expanded bounding box; reject edge touching too.
        guard !overlapsExpandedSource(destination, source: source, gap: gap) else { return .rejected(.destinationOverlapsRegion) }
        return .accepted(PatchPlacement(ellipse: ellipse, source: source, destination: destination,
                                        safetyGapPoints: gap))
    }

    private static func validRectangle(_ rectangle: ScreenRect) -> Bool {
        rectangle.x.isFinite && rectangle.y.isFinite && rectangle.width.isFinite && rectangle.height.isFinite
            && rectangle.width > 0 && rectangle.height > 0
            && (rectangle.x + rectangle.width).isFinite && (rectangle.y + rectangle.height).isFinite
    }

    private static func contains(_ outer: ScreenRect, _ inner: ScreenRect) -> Bool {
        validRectangle(inner) && inner.x >= outer.x && inner.y >= outer.y
            && inner.x + inner.width <= outer.x + outer.width
            && inner.y + inner.height <= outer.y + outer.height
    }

    private static func overlapsExpandedSource(_ destination: ScreenRect, source: ScreenRect, gap: Double) -> Bool {
        destination.x <= source.x + source.width + gap && destination.x + destination.width >= source.x - gap
            && destination.y <= source.y + source.height + gap && destination.y + destination.height >= source.y - gap
    }
}
