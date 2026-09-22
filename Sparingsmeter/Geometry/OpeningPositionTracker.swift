import Foundation
import simd

struct OpeningPositionEstimate: Sendable, Equatable {
    let center: SIMD3<Float>
    let width: Float
    let height: Float
    let lines: [DebugBoundaryLine]
}

struct OpeningPositionLock: Sendable, Equatable {
    let progress: Double
    let isLocked: Bool
    let estimate: OpeningPositionEstimate?
}

struct OpeningPositionTracker {
    private var history: [OpeningPositionEstimate] = []
    private let maxHistory = 24
    private let minimumLockSamples = 12
    private let maximumCenterSpread: Float = 0.05
    private let maximumRelativeSizeSpread: Float = 0.10

    mutating func reset() {
        history.removeAll(keepingCapacity: true)
    }

    mutating func add(lines: [DebugBoundaryLine]) -> OpeningPositionLock {
        guard let estimate = Self.estimate(from: lines) else {
            return currentLock
        }
        history.append(estimate)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        return currentLock
    }

    var currentLock: OpeningPositionLock {
        guard history.count >= 3 else {
            return OpeningPositionLock(
                progress: min(0.2, Double(history.count) / Double(minimumLockSamples)),
                isLocked: false,
                estimate: history.last
            )
        }

        let recent = Array(history.suffix(minimumLockSamples))
        let centers = recent.map(\.center)
        let meanCenter = centers.reduce(SIMD3<Float>(repeating: 0), +) / Float(centers.count)
        let maxCenterDistance = centers.map { simd_distance($0, meanCenter) }.max() ?? .greatestFiniteMagnitude

        let widths = recent.map(\.width)
        let heights = recent.map(\.height)
        let widthMean = widths.reduce(0, +) / Float(widths.count)
        let heightMean = heights.reduce(0, +) / Float(heights.count)
        let widthSpread = Self.relativeSpread(widths, mean: widthMean)
        let heightSpread = Self.relativeSpread(heights, mean: heightMean)

        let sampleScore = min(1.0, Double(history.count) / Double(minimumLockSamples))
        let centerScore = max(0.0, min(1.0, 1.0 - Double(maxCenterDistance / maximumCenterSpread)))
        let sizeScore = max(
            0.0,
            min(
                1.0,
                1.0 - Double(max(widthSpread, heightSpread) / maximumRelativeSizeSpread)
            )
        )
        let progress = min(1.0, sampleScore * 0.35 + centerScore * 0.40 + sizeScore * 0.25)
        let locked = history.count >= minimumLockSamples
            && maxCenterDistance <= maximumCenterSpread
            && widthSpread <= maximumRelativeSizeSpread
            && heightSpread <= maximumRelativeSizeSpread

        return OpeningPositionLock(
            progress: progress,
            isLocked: locked,
            estimate: locked ? recent.last : history.last
        )
    }

    private static func estimate(from lines: [DebugBoundaryLine]) -> OpeningPositionEstimate? {
        guard lines.count == 4 else { return nil }

        let points = lines.flatMap { [$0.start, $0.end] }
        let center = points.reduce(SIMD3<Float>(repeating: 0), +) / Float(points.count)

        let lengths = lines.map { simd_distance($0.start, $0.end) }.sorted()
        guard lengths.count == 4 else { return nil }

        let shortMean = (lengths[0] + lengths[1]) * 0.5
        let longMean = (lengths[2] + lengths[3]) * 0.5
        guard shortMean > 0.10, longMean > 0.10 else { return nil }

        return OpeningPositionEstimate(
            center: center,
            width: shortMean,
            height: longMean,
            lines: lines
        )
    }

    private static func relativeSpread(_ values: [Float], mean: Float) -> Float {
        guard mean > 0.001 else { return .greatestFiniteMagnitude }
        let minValue = values.min() ?? mean
        let maxValue = values.max() ?? mean
        return (maxValue - minValue) / mean
    }
}
