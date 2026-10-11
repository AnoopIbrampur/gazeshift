import Foundation
import GazeShiftCore

/// Backup demo without eye tracking: the user circles a region on the live rear view with a finger;
/// the enclosing rectangle is copied (original pixels) to a draggable destination, and the circled
/// spot can be blurred to simulate the blind area. All values are viewport points, top-left origin.
public struct TouchRelocation: Equatable, Sendable {
    public static let minimumSide = 24.0
    /// Rule-of-thirds anchors in normalized viewport units.
    public static let thirds = [ScreenPoint(x: 1.0 / 3, y: 1.0 / 3), ScreenPoint(x: 2.0 / 3, y: 1.0 / 3),
                                ScreenPoint(x: 1.0 / 3, y: 2.0 / 3), ScreenPoint(x: 2.0 / 3, y: 2.0 / 3)]

    public let viewWidth: Double
    public let viewHeight: Double
    public private(set) var stroke: [ScreenPoint] = []
    public private(set) var source: ScreenRect?
    public private(set) var destination: ScreenRect?

    public init(viewWidth: Double, viewHeight: Double) {
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
    }

    public var isDrawing: Bool { source == nil && !stroke.isEmpty }

    /// Starts a new circle, discarding any previous region.
    public mutating func begin(at point: ScreenPoint) {
        stroke = [clamp(point)]
        source = nil
        destination = nil
    }

    public mutating func add(_ point: ScreenPoint) {
        guard source == nil, !stroke.isEmpty, point.isFinite else { return }
        stroke.append(clamp(point))
    }

    /// Ends the circle. Returns false (and clears) when the drawn area is too small to copy.
    @discardableResult
    public mutating func finish() -> Bool {
        let xs = stroke.map(\.x), ys = stroke.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX - minX >= Self.minimumSide, maxY - minY >= Self.minimumSide else {
            reset()
            return false
        }
        let region = ScreenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        source = region
        destination = defaultDestination(for: region)
        return true
    }

    /// Moves the copy so its top-left is `origin`, kept fully inside the view.
    public mutating func moveDestination(to origin: ScreenPoint) {
        guard let current = destination, origin.isFinite else { return }
        destination = ScreenRect(x: min(max(origin.x, 0), viewWidth - current.width),
                                 y: min(max(origin.y, 0), viewHeight - current.height),
                                 width: current.width, height: current.height)
    }

    public mutating func reset() {
        stroke = []
        source = nil
        destination = nil
    }

    /// Shader values: copy source→destination from original pixels; optional blur over the circled
    /// ellipse, applied last.
    public func uniforms(blurSource: Bool, kernelPoints: Double = 22) -> CompositeUniformValues.GPU? {
        guard let source, let destination, viewWidth > 0, viewHeight > 0 else { return nil }
        func uv(_ x: Double, _ y: Double) -> SIMD2<Float> { SIMD2(Float(x / viewWidth), Float(y / viewHeight)) }
        return CompositeUniformValues.GPU(
            sourceOrigin: uv(source.x, source.y), destinationOrigin: uv(destination.x, destination.y),
            copySize: uv(source.width, source.height),
            blurCenter: uv(source.x + source.width / 2, source.y + source.height / 2),
            blurRadii: uv(source.width / 2, source.height / 2), blurKernel: uv(kernelPoints, kernelPoints),
            copyEnabled: 1, blurEnabled: blurSource ? 1 : 0)
    }

    /// Centers the copy on the rule-of-thirds point farthest from the circled region, inside the view.
    private func defaultDestination(for region: ScreenRect) -> ScreenRect {
        let center = ScreenPoint(x: region.x + region.width / 2, y: region.y + region.height / 2)
        let anchor = Self.thirds.map { ScreenPoint(x: $0.x * viewWidth, y: $0.y * viewHeight) }
            .max { hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y) }!
        let x = min(max(anchor.x - region.width / 2, 0), max(viewWidth - region.width, 0))
        let y = min(max(anchor.y - region.height / 2, 0), max(viewHeight - region.height, 0))
        return ScreenRect(x: x, y: y, width: region.width, height: region.height)
    }

    private func clamp(_ point: ScreenPoint) -> ScreenPoint {
        ScreenPoint(x: min(max(point.x, 0), viewWidth), y: min(max(point.y, 0), viewHeight))
    }
}
