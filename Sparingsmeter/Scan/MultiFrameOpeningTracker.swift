import CoreGraphics
import Foundation

struct TrackedOpening: Sendable, Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    let observationCount: Int
    let meanConfidence: Float
    let stability: Double

    var boundingBox: CGRect {
        let xs = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x]
        let ys = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y]
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Tracks whether Vision is consistently seeing the same *shape*.
///
/// Important: image-space position is deliberately NOT part of stability.
/// During a real scan the operator moves the camera around the opening, so
/// the rectangle is expected to translate and scale in the camera image.
/// Using image-coordinate jitter as stability would punish the exact movement
/// the scan workflow requires.
struct MultiFrameOpeningTracker {
    private(set) var observations: [OpeningObservation] = []
    let maximumObservationCount = 90
    let stabilityWindow = 12

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }

    mutating func add(_ observation: OpeningObservation) {
        observations.append(observation)
        if observations.count > maximumObservationCount {
            observations.removeFirst(observations.count - maximumObservationCount)
        }
    }

    var trackedOpening: TrackedOpening? {
        guard observations.count >= 5, let latest = observations.last else { return nil }

        let recent = Array(observations.suffix(stabilityWindow))
        let confidence = recent.map(\.confidence).reduce(0, +) / Float(recent.count)

        let aspects = recent.map { aspectRatio(of: $0) }
        let aspectMedian = median(aspects)
        let aspectDeviation = meanAbsoluteDeviation(aspects, around: aspectMedian)

        let rectangularities = recent.map(rectangularity)
        let rectangularityMean = rectangularities.reduce(0, +) / Double(rectangularities.count)

        // Shape consistency is translation/scale invariant. A moving camera may
        // alter perspective somewhat, so keep this intentionally forgiving.
        let aspectScore = max(0.0, min(1.0, 1.0 - aspectDeviation * 5.0))
        let confidenceScore = max(0.0, min(1.0, Double(confidence)))
        let stability = max(
            0.0,
            min(1.0, aspectScore * 0.55 + rectangularityMean * 0.30 + confidenceScore * 0.15)
        )

        // Use the latest Vision corners for the current ARFrame. Never use the
        // median image position over frames from different camera poses.
        return TrackedOpening(
            topLeft: latest.topLeft,
            topRight: latest.topRight,
            bottomLeft: latest.bottomLeft,
            bottomRight: latest.bottomRight,
            observationCount: observations.count,
            meanConfidence: confidence,
            stability: stability
        )
    }

    private func aspectRatio(of observation: OpeningObservation) -> Double {
        let width = (
            distance(observation.topLeft, observation.topRight)
            + distance(observation.bottomLeft, observation.bottomRight)
        ) / 2.0
        let height = (
            distance(observation.topLeft, observation.bottomLeft)
            + distance(observation.topRight, observation.bottomRight)
        ) / 2.0
        guard height > 0.0001 else { return 0 }
        return width / height
    }

    private func rectangularity(_ observation: OpeningObservation) -> Double {
        let top = distance(observation.topLeft, observation.topRight)
        let bottom = distance(observation.bottomLeft, observation.bottomRight)
        let left = distance(observation.topLeft, observation.bottomLeft)
        let right = distance(observation.topRight, observation.bottomRight)

        let horizontal = similarity(top, bottom)
        let vertical = similarity(left, right)
        return (horizontal + vertical) / 2.0
    }

    private func similarity(_ a: Double, _ b: Double) -> Double {
        let maximum = max(a, b)
        guard maximum > 0.0001 else { return 0 }
        return max(0.0, min(1.0, 1.0 - abs(a - b) / maximum))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private func meanAbsoluteDeviation(_ values: [Double], around centre: Double) -> Double {
        guard !values.isEmpty else { return 1 }
        return values.map { abs($0 - centre) }.reduce(0, +) / Double(values.count)
    }
}
