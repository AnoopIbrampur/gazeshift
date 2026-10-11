import Foundation
import GazeNumerics

public struct GazeCalibration: Sendable {
    // Small normalized-predictor penalty; provisional until measured on the device.
    public static let regularization = 1e-6
    public static let rankTolerance = 1e-10
    private static let featureCount = 3
    private static let penaltyRows = 2

    public let geometry: RenderGeometry
    private let mean: ScreenPoint
    private let spread: ScreenPoint
    private let xCoefficients: [Double]
    private let yCoefficients: [Double]

    public static func fit(samples: [CalibrationSample], geometry: RenderGeometry) throws -> GazeCalibration {
        guard samples.count >= featureCount,
              samples.count <= Int(Int32.max) - penaltyRows
        else { throw GazeCoreError.insufficientCalibration }
        guard samples.allSatisfy({ $0.target.isFinite }) else { throw GazeCoreError.invalidLabel }
        let h = samples.map(\.features.horizontal)
        let v = samples.map(\.features.vertical)
        let horizontal = try normalize(h)
        let vertical = try normalize(v)
        let rawRows = samples.count
        let rawDesign = Array(repeating: 1.0, count: rawRows) + horizontal.values + vertical.values
        let rawTargets = samples.map(\.target.x) + samples.map(\.target.y)
        // The unregularized rank check is essential: ridge alone would fit a line or a constant.
        _ = try solve(design: rawDesign, targets: rawTargets, rows: rawRows)

        let rows = rawRows + penaltyRows
        let penalty = sqrt(regularization)
        // Explicit element types keep this concatenation within the type checker's time budget.
        let interceptColumn: [Double] = Array(repeating: 1.0, count: rawRows) + [0, 0]
        let horizontalColumn: [Double] = horizontal.values + [penalty, 0]
        let verticalColumn: [Double] = vertical.values + [0, penalty]
        let design: [Double] = interceptColumn + horizontalColumn + verticalColumn
        let xTargets: [Double] = samples.map(\.target.x) + [0, 0]
        let yTargets: [Double] = samples.map(\.target.y) + [0, 0]
        let targets: [Double] = xTargets + yTargets
        let coefficients = try solve(design: design, targets: targets, rows: rows)
        return GazeCalibration(geometry: geometry,
                               mean: ScreenPoint(x: horizontal.mean, y: vertical.mean),
                               spread: ScreenPoint(x: horizontal.spread, y: vertical.spread),
                               xCoefficients: coefficients.x, yCoefficients: coefficients.y)
    }

    /// Returns raw view points, including finite off-screen estimates for honest scoring.
    public func predict(features: EyeFeatures, geometry: RenderGeometry) throws -> ScreenPoint {
        guard geometry == self.geometry else { throw GazeCoreError.geometryChanged }
        let h = (features.horizontal - mean.x) / spread.x
        let v = (features.vertical - mean.y) / spread.y
        let point = ScreenPoint(x: xCoefficients[0] + xCoefficients[1] * h + xCoefficients[2] * v,
                                y: yCoefficients[0] + yCoefficients[1] * h + yCoefficients[2] * v)
        guard point.isFinite else { throw GazeCoreError.numericalFailure }
        return point
    }

    public func livePrediction(observation: GazeObservation?, now: Double,
                               geometry: RenderGeometry) -> ScreenPoint? {
        guard GazeQuality.rejectionReason(observation: observation, now: now) == nil,
              let features = observation?.features,
              let prediction = try? predict(features: features, geometry: geometry),
              geometry.contains(prediction) else { return nil }
        return prediction
    }

    private static func normalize(_ values: [Double]) throws -> (values: [Double], mean: Double, spread: Double) {
        let count = Double(values.count)
        let mean = values.reduce(0) { $0 + $1 / count }
        let centered = values.map { $0 - mean }
        let spread = sqrt(centered.reduce(0) { $0 + ($1 * $1) / count })
        guard mean.isFinite, spread.isFinite else { throw GazeCoreError.numericalFailure }
        guard spread > 0 else { throw GazeCoreError.degenerateCalibration }
        let normalized = centered.map { $0 / spread }
        guard normalized.allSatisfy(\.isFinite) else { throw GazeCoreError.numericalFailure }
        return (normalized, mean, spread)
    }

    private static func solve(design: [Double], targets: [Double], rows: Int) throws -> (x: [Double], y: [Double]) {
        var matrix = design
        var rightHandSides = targets
        var rank: Int32 = 0
        let status = gaze_solve_affine(Int32(rows), &matrix, &rightHandSides, rankTolerance, &rank)
        guard status == 0 else { throw GazeCoreError.numericalFailure }
        guard rank == featureCount else { throw GazeCoreError.degenerateCalibration }
        let x = Array(rightHandSides[0..<featureCount])
        let y = Array(rightHandSides[rows..<(rows + featureCount)])
        guard (x + y).allSatisfy(\.isFinite) else { throw GazeCoreError.numericalFailure }
        return (x, y)
    }
}
