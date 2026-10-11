import Foundation

public enum HeldOutTarget: String, CaseIterable, Sendable {
    case upperLeft, upperRight, lowerLeft, lowerRight, centerControl
    public static let novelTargets: [HeldOutTarget] = [.upperLeft, .upperRight, .lowerLeft, .lowerRight]

    public var normalized: ScreenPoint {
        switch self {
        case .upperLeft: ScreenPoint(x: 0.25, y: 0.25)
        case .upperRight: ScreenPoint(x: 0.75, y: 0.25)
        case .lowerLeft: ScreenPoint(x: 0.25, y: 0.75)
        case .lowerRight: ScreenPoint(x: 0.75, y: 0.75)
        case .centerControl: ScreenPoint(x: 0.5, y: 0.5)
        }
    }
}

public enum HeldOutPolicy {
    // Predeclared provisional engineering gates from BUILD_PROMPTS, never adjusted to a result.
    public static let settlingSeconds = 0.5
    public static let windowSeconds = 1.0
    public static let slotSeconds = 0.05
    public static let slots = 20
    public static let passes = 2
    public static let minimumValidFraction = 0.8
    public static let minimumDistinctPredictions = 10
    public static let maximumMedianFraction = 0.1
    public static let maximumP90Fraction = 0.2
}

public struct ErrorStatistics: Sendable {
    public let medianPoints: Double
    public let p90Points: Double
    public let medianDiagonalFraction: Double
    public let p90DiagonalFraction: Double

    fileprivate init?(distances: [Double], diagonal: Double) {
        guard !distances.isEmpty else { return nil }
        let sorted = distances.sorted()
        let middle = sorted.count / 2
        medianPoints = sorted.count.isMultiple(of: 2)
            ? sorted[middle - 1] * 0.5 + sorted[middle] * 0.5 : sorted[middle]
        // Nearest-rank p90; choosing an actual error avoids interpolating away a bad tail.
        p90Points = sorted[Int(ceil(0.9 * Double(sorted.count))) - 1]
        medianDiagonalFraction = medianPoints / diagonal
        p90DiagonalFraction = p90Points / diagonal
    }

    fileprivate var passes: Bool {
        medianDiagonalFraction <= HeldOutPolicy.maximumMedianFraction
            && p90DiagonalFraction <= HeldOutPolicy.maximumP90Fraction
    }
}

public struct HeldOutWindowResult: Sendable {
    public let target: HeldOutTarget
    public let pass: Int
    public let geometry: RenderGeometry
    public let expectedSlots = HeldOutPolicy.slots
    public let validPredictions: Int
    public let receivedUniqueSamples: Int
    public let rejectedSlots: Int
    public let rejectionCounts: [RejectionReason: Int]
    public let errors: ErrorStatistics?
    public let passesNumericalGate: Bool
    public let validFraction: Double
    fileprivate let distances: [Double]

    fileprivate init(target: HeldOutTarget, pass: Int, geometry: RenderGeometry,
                     distances: [Double], received: Int, rejections: [RejectionReason: Int]) {
        self.target = target
        self.pass = pass
        self.geometry = geometry
        self.distances = distances
        validPredictions = distances.count
        receivedUniqueSamples = received
        rejectedSlots = HeldOutPolicy.slots - distances.count
        rejectionCounts = rejections
        validFraction = Double(distances.count) / Double(HeldOutPolicy.slots)
        errors = ErrorStatistics(distances: distances, diagonal: geometry.diagonal)
        passesNumericalGate = validFraction >= HeldOutPolicy.minimumValidFraction
            && distances.count >= HeldOutPolicy.minimumDistinctPredictions && errors?.passes == true
    }
}

public struct HeldOutWindow {
    public let target: HeldOutTarget
    public let pass: Int
    public let geometry: RenderGeometry
    public let startsAt: Double
    public let endsAt: Double
    private var recordedSlots = Set<Int>()
    private var receivedTimestamps = Set<Double>()
    private var distances: [Double] = []
    private var rejections: [RejectionReason: Int] = [:]

    public init(target: HeldOutTarget, pass: Int, presentedAt: Double, geometry: RenderGeometry) throws {
        let start = presentedAt + HeldOutPolicy.settlingSeconds
        let end = start + HeldOutPolicy.windowSeconds
        guard (1...HeldOutPolicy.passes).contains(pass), presentedAt.isFinite,
              start.isFinite, end.isFinite, end > start else { throw GazeCoreError.invalidWindow }
        self.target = target
        self.pass = pass
        self.geometry = geometry
        startsAt = start
        endsAt = end
    }

    public mutating func record(slot: Int, now: Double, observation: GazeObservation?,
                                calibration: GazeCalibration) throws {
        guard (0..<HeldOutPolicy.slots).contains(slot) else { throw GazeCoreError.invalidSlot }
        guard recordedSlots.insert(slot).inserted else { throw GazeCoreError.duplicateSlot }
        if let reason = sampleRejection(slot: slot, now: now, observation: observation) {
            rejections[reason, default: 0] += 1
            return
        }
        guard calibration.geometry == geometry else {
            rejections[.geometryChanged, default: 0] += 1
            return
        }
        guard let features = observation?.features,
              let prediction = try? calibration.predict(features: features, geometry: geometry) else {
            rejections[.nonfinitePrediction, default: 0] += 1
            return
        }
        let targetPoint = ScreenPoint(x: target.normalized.x * geometry.width,
                                      y: target.normalized.y * geometry.height)
        // Deliberately no contains/clamp check: finite off-screen predictions are scored too.
        distances.append(hypot(prediction.x - targetPoint.x, prediction.y - targetPoint.y))
    }

    public func finish() -> HeldOutWindowResult {
        var completedRejections = rejections
        let missing = HeldOutPolicy.slots - recordedSlots.count
        if missing > 0 { completedRejections[.missing, default: 0] += missing }
        return HeldOutWindowResult(target: target, pass: pass, geometry: geometry,
                                   distances: distances, received: receivedTimestamps.count,
                                   rejections: completedRejections)
    }

    private mutating func sampleRejection(slot: Int, now: Double,
                                         observation: GazeObservation?) -> RejectionReason? {
        let scheduledStart = startsAt + Double(slot) * HeldOutPolicy.slotSeconds
        let scheduledEnd = startsAt + Double(slot + 1) * HeldOutPolicy.slotSeconds
        guard now.isFinite else { return .nonfinite }
        guard now >= scheduledStart, now < scheduledEnd else { return .missedSchedule }
        guard let observation else { return .missing }
        guard observation.timestamp.isFinite else { return .nonfinite }
        guard observation.timestamp >= startsAt, observation.timestamp < endsAt else { return .outsideWindow }
        guard receivedTimestamps.insert(observation.timestamp).inserted else { return .duplicate }
        return GazeQuality.rejectionReason(observation: observation, now: now)
    }
}

public enum EyeOnlyResponse: Sendable { case notTested, observedPass, observedFail }

public struct HeldOutReport: Sendable {
    public let passesNumericalGate: Bool
    public let passesCompleteGate: Bool
    public let novelWindows: [HeldOutWindowResult]
    public let centerControls: [HeldOutWindowResult]
    public let overallValidPredictions: Int
    public let overallReceivedUniqueSamples: Int
    public let overallRejectedSlots: Int
    public let overallRejectionCounts: [RejectionReason: Int]
    public let overallErrors: ErrorStatistics?
    public let overallValidFraction: Double
    public let eyeOnlyResponse: EyeOnlyResponse

    public init(windows: [HeldOutWindowResult], geometry: RenderGeometry,
                eyeOnlyResponse: EyeOnlyResponse = .notTested) throws {
        var supplied: [String: HeldOutWindowResult] = [:]
        for window in windows {
            guard window.geometry == geometry else { throw GazeCoreError.geometryChanged }
            let key = Self.key(window.target, window.pass)
            guard supplied.updateValue(window, forKey: key) == nil else { throw GazeCoreError.duplicateWindow }
        }
        var novel: [HeldOutWindowResult] = []
        for pass in 1...HeldOutPolicy.passes {
            for target in HeldOutTarget.novelTargets {
                if let result = supplied[Self.key(target, pass)] { novel.append(result) }
                else {
                    novel.append(HeldOutWindowResult(target: target, pass: pass, geometry: geometry,
                                                     distances: [], received: 0,
                                                     rejections: [.missing: HeldOutPolicy.slots]))
                }
            }
        }
        novelWindows = novel
        centerControls = windows.filter { $0.target == .centerControl }.sorted { $0.pass < $1.pass }
        let distances = novel.flatMap(\.distances)
        overallValidPredictions = distances.count
        overallReceivedUniqueSamples = novel.reduce(0) { $0 + $1.receivedUniqueSamples }
        overallRejectedSlots = novel.reduce(0) { $0 + $1.rejectedSlots }
        overallRejectionCounts = novel.reduce(into: [:]) { counts, window in
            for (reason, count) in window.rejectionCounts { counts[reason, default: 0] += count }
        }
        overallErrors = ErrorStatistics(distances: distances, diagonal: geometry.diagonal)
        overallValidFraction = Double(distances.count) / Double(novel.count * HeldOutPolicy.slots)
        passesNumericalGate = novel.allSatisfy(\.passesNumericalGate) && overallErrors?.passes == true
        self.eyeOnlyResponse = eyeOnlyResponse
        passesCompleteGate = passesNumericalGate && eyeOnlyResponse == .observedPass
    }

    private static func key(_ target: HeldOutTarget, _ pass: Int) -> String { "\(target.rawValue):\(pass)" }
}
