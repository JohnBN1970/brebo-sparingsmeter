import CoreImage
import CoreVideo
import Foundation
import Vision

final class VisionOpeningDetector {
    private let queue = DispatchQueue(label: "nl.brebo.sparingsmeter.vision", qos: .userInitiated)
    private var isProcessing = false

    func detectOpening(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right,
        completion: @escaping @Sendable (OpeningObservation?) -> Void
    ) {
        guard !isProcessing else { return }
        isProcessing = true

        queue.async { [weak self] in
            defer { self?.isProcessing = false }

            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 8
            request.minimumConfidence = 0.45
            request.minimumAspectRatio = 0.12
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.10
            request.quadratureTolerance = 28

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )

            do {
                try handler.perform([request])

                let candidate = (request.results ?? [])
                    .filter { $0.boundingBox.width > 0.12 && $0.boundingBox.height > 0.12 }
                    .sorted {
                        let area0 = $0.boundingBox.width * $0.boundingBox.height
                        let area1 = $1.boundingBox.width * $1.boundingBox.height
                        if abs(area0 - area1) > 0.02 {
                            return area0 > area1
                        }
                        return $0.confidence > $1.confidence
                    }
                    .first

                guard let candidate else {
                    completion(nil)
                    return
                }

                completion(
                    OpeningObservation(
                        topLeft: candidate.topLeft,
                        topRight: candidate.topRight,
                        bottomLeft: candidate.bottomLeft,
                        bottomRight: candidate.bottomRight,
                        confidence: candidate.confidence,
                        timestamp: Date().timeIntervalSince1970
                    )
                )
            } catch {
                completion(nil)
            }
        }
    }
}
