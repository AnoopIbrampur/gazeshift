import Foundation

public struct ScreenPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var isFinite: Bool { x.isFinite && y.isFinite }
}

public enum DisplayOrientation: String, Sendable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight
}

public enum TrackingMode: String, Sendable { case frontSetup, rearLive }

public enum GazeCoreError: Error {
    case invalidGeometry, invalidFeatures, insufficientCalibration, degenerateCalibration
    case invalidLabel, numericalFailure, geometryChanged, invalidWindow
    case invalidSlot, duplicateSlot, duplicateWindow
}

/// Full display-view identity. Camera image UV coordinates are deliberately separate.
public struct RenderGeometry: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let scale: Double
    public let orientation: DisplayOrientation
    public let mode: TrackingMode
    public let viewingSetupID: String

    public init(width: Double, height: Double, scale: Double,
                orientation: DisplayOrientation, mode: TrackingMode,
                viewingSetupID: String) throws {
        guard width.isFinite, height.isFinite, scale.isFinite,
              width > 0, height > 0, scale > 0,
              hypot(width, height).isFinite,
              (width * scale).isFinite, (height * scale).isFinite,
              !(viewingSetupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        else { throw GazeCoreError.invalidGeometry }
        self.width = width
        self.height = height
        self.scale = scale
        self.orientation = orientation
        self.mode = mode
        self.viewingSetupID = viewingSetupID
    }

    public var diagonal: Double { hypot(width, height) }

    public func normalized(_ point: ScreenPoint) -> ScreenPoint {
        ScreenPoint(x: point.x / width, y: point.y / height)
    }

    public func pixels(_ point: ScreenPoint) -> ScreenPoint {
        ScreenPoint(x: point.x * scale, y: point.y * scale)
    }

    public func contains(_ point: ScreenPoint) -> Bool {
        point.isFinite && point.x >= 0 && point.x <= width && point.y >= 0 && point.y <= height
    }
}

public struct EyeFeatures: Sendable {
    // Provisional numerical guard, not an empirical gaze-confidence threshold.
    public static let minimumDirectionDepth = 1e-6
    public let horizontal: Double
    public let vertical: Double

    public init(horizontal: Double, vertical: Double) throws {
        guard horizontal.isFinite, vertical.isFinite else { throw GazeCoreError.invalidFeatures }
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Inputs must all be in the same ARFaceAnchor face coordinate system.
    public static func from(leftEye: SIMD3<Double>, rightEye: SIMD3<Double>,
                            lookAtPoint: SIMD3<Double>) throws -> EyeFeatures {
        guard [leftEye, rightEye, lookAtPoint].allSatisfy({ vector in
            vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
        }) else { throw GazeCoreError.invalidFeatures }
        let midpoint = leftEye * 0.5 + rightEye * 0.5
        let direction = lookAtPoint - midpoint
        guard direction.z.isFinite, abs(direction.z) >= minimumDirectionDepth
        else { throw GazeCoreError.invalidFeatures }
        return try EyeFeatures(horizontal: direction.x / direction.z,
                               vertical: direction.y / direction.z)
    }
}

public struct CalibrationSample: Sendable {
    public let features: EyeFeatures
    public let target: ScreenPoint

    public init(features: EyeFeatures, target: ScreenPoint) {
        self.features = features
        self.target = target
    }
}

public struct GazeObservation: Sendable {
    public let timestamp: Double
    public let isTracked: Bool
    public let leftBlink: Double?
    public let rightBlink: Double?
    public let features: EyeFeatures?

    public init(timestamp: Double, isTracked: Bool, leftBlink: Double?,
                rightBlink: Double?, features: EyeFeatures?) {
        self.timestamp = timestamp
        self.isTracked = isTracked
        self.leftBlink = leftBlink
        self.rightBlink = rightBlink
        self.features = features
    }
}

public enum RejectionReason: String, Hashable, Sendable {
    case missing, duplicate, stale, untracked, closedEyes, missingQuality, invalidQuality
    case nonfinite, outsideWindow, missedSchedule, futureTimestamp, geometryChanged, nonfinitePrediction
}

public enum GazeQuality {
    // BUILD_PROMPTS provisional engineering thresholds; physical verification is still required.
    public static let maximumSampleAge = 0.250
    public static let maximumEyeBlink = 0.6

    public static func rejectionReason(observation: GazeObservation?, now: Double) -> RejectionReason? {
        guard let observation else { return .missing }
        guard now.isFinite, observation.timestamp.isFinite else { return .nonfinite }
        guard observation.timestamp <= now else { return .futureTimestamp }
        guard now - observation.timestamp <= maximumSampleAge else { return .stale }
        guard observation.isTracked else { return .untracked }
        guard let left = observation.leftBlink, let right = observation.rightBlink,
              observation.features != nil else { return .missingQuality }
        guard left.isFinite, right.isFinite else { return .nonfinite }
        guard left >= 0, right >= 0, left <= 1, right <= 1 else { return .invalidQuality }
        guard left < maximumEyeBlink, right < maximumEyeBlink else { return .closedEyes }
        return nil
    }
}
