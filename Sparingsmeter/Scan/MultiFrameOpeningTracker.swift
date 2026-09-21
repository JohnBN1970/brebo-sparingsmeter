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

struct MultiFrameOpeningTracker {
    private(set) var observations: [OpeningObservation] = []
    let maximumObservationCount = 90

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
        guard observations.count >= 5 else { return nil }

        let tl = medianPoint(observations.map(\.topLeft))
        let tr = medianPoint(observations.map(\.topRight))
        let bl = medianPoint(observations.map(\.bottomLeft))
        let br = medianPoint(observations.map(\.bottomRight))

        let confidence = observations.map(\.confidence).reduce(0, +) / Float(observations.count)

        let jitter = (
            pointJitter(observations.map(\.topLeft), around: tl)
            + pointJitter(observations.map(\.topRight), around: tr)
            + pointJitter(observations.map(\.bottomLeft), around: bl)
            + pointJitter(observations.map(\.bottomRight), around: br)
        ) / 4.0

        let stability = max(0.0, min(1.0, 1.0 - jitter * 18.0))

        return TrackedOpening(
            topLeft: tl,
            topRight: tr,
            bottomLeft: bl,
            bottomRight: br,
            observationCount: observations.count,
            meanConfidence: confidence,
            stability: stability
        )
    }

    private func medianPoint(_ points: [CGPoint]) -> CGPoint {
        CGPoint(x: median(points.map(\.x)), y: median(points.map(\.y)))
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private func pointJitter(_ points: [CGPoint], around centre: CGPoint) -> Double {
        guard !points.isEmpty else { return 1 }
        let total = points.reduce(0.0) { partial, point in
            let dx = Double(point.x - centre.x)
            let dy = Double(point.y - centre.y)
            return partial + (dx * dx + dy * dy).squareRoot()
        }
        return total / Double(points.count)
    }
}
