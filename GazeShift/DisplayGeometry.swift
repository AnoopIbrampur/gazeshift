import CoreGraphics
import ImageIO

/// One raw camera image → canonical display map, shared by landmarks and rendering.
struct DisplayGeometry {
    let rawToDisplay: CGAffineTransform
    let orientation: CGImagePropertyOrientation
    private let orientedToRaw: CGAffineTransform
    private let inverseDisplay: CGAffineTransform

    init?(viewport: CGSize, displayTransform: CGAffineTransform, orientation: CGImagePropertyOrientation, mirrored: Bool) {
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0,
              [displayTransform.a, displayTransform.b, displayTransform.c, displayTransform.d, displayTransform.tx, displayTransform.ty].allSatisfy(\.isFinite),
              abs(displayTransform.a * displayTransform.d - displayTransform.b * displayTransform.c) > 0.000001 else { return nil }
        self.orientation = orientation
        // ARKit supplies rotation/aspect fill; deliberate front-preview mirror follows once.
        rawToDisplay = mirrored ? displayTransform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)) : displayTransform
        inverseDisplay = rawToDisplay.inverted()
        orientedToRaw = Self.rawToOriented(orientation).inverted()
    }

    func visionToDisplay(_ point: CGPoint) -> CGPoint {
        // Vision is lower-left in its EXIF-oriented image; undo EXIF before ARKit crop.
        CGPoint(x: point.x, y: 1 - point.y).applying(orientedToRaw).applying(rawToDisplay)
    }
    func displayToRaw(_ point: CGPoint) -> CGPoint { point.applying(inverseDisplay) }

    private static func rawToOriented(_ orientation: CGImagePropertyOrientation) -> CGAffineTransform {
        switch orientation {
        case .up: return .identity
        case .upMirrored: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)
        case .down: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
        case .downMirrored: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
        case .leftMirrored: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .rightMirrored: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 1, ty: 1)
        case .left: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1)
        @unknown default: return .identity
        }
    }
}
