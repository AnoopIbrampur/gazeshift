import Vision
import CoreVideo
import ImageIO

struct HandWork {
    let identity: FrameIdentity
    let image: CVPixelBuffer
    let geometry: DisplayGeometry
}

/// Call only from the owner's serial queue. Vision itself runs synchronously on one worker.
final class HandTracker {
    private let ownerQueue: DispatchQueue
    private let worker = DispatchQueue(label: "com.gazeshift.hand-vision", qos: .userInitiated)
    private var work = NewestWorkQueue<HandWork>()
    private let completion: (HandWork, Result<HandObservation?, Error>) -> Void

    init(ownerQueue: DispatchQueue, completion: @escaping (HandWork, Result<HandObservation?, Error>) -> Void) {
        self.ownerQueue = ownerQueue
        self.completion = completion
    }

    func submit(_ item: HandWork) {
        if let next = work.offer(item) { perform(next) }
    }

    func invalidatePending() {
        // Do not release in-flight ownership: the old request must actually return first.
        work.clearPending()
    }

    private func perform(_ item: HandWork) {
        worker.async { [weak self] in
            guard let self else { return }
            let result = Result { try Self.detect(item) }
            self.ownerQueue.async {
                self.completion(item, result)
                if let next = self.work.complete() { self.perform(next) }
            }
        }
    }

    private static func detect(_ item: HandWork) throws -> HandObservation? {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        try VNImageRequestHandler(cvPixelBuffer: item.image, orientation: item.geometry.orientation, options: [:]).perform([request])
        guard let observation = request.results?.first else { return nil }
        let index = try observation.recognizedPoint(.indexTip)
        let thumb = try observation.recognizedPoint(.thumbTip)
        guard index.confidence >= CaptureLimits.minimumHandJointConfidence,
              thumb.confidence >= CaptureLimits.minimumHandJointConfidence,
              [index.location.x, index.location.y, thumb.location.x, thumb.location.y].allSatisfy(\.isFinite) else { return nil }
        let indexDisplay = item.geometry.visionToDisplay(index.location)
        let thumbDisplay = item.geometry.visionToDisplay(thumb.location)
        guard [indexDisplay, thumbDisplay].allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return nil }
        return HandObservation(identity: item.identity, indexTip: indexDisplay, thumbTip: thumbDisplay, indexConfidence: index.confidence, thumbConfidence: thumb.confidence)
    }
}
