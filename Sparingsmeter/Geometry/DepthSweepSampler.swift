import ARKit
import CoreGraphics
import CoreVideo
import Foundation
import simd

struct PartialEdgeCandidates: Sendable {
    var vertical: [SIMD3<Float>] = []
    var horizontal: [SIMD3<Float>] = []
    var totalCount: Int { vertical.count + horizontal.count }

    /// Conservative first-pass structural filter for the debug build.
    /// A point must have nearby support along the expected physical edge direction.
    var structurallySupported: PartialEdgeCandidates {
        PartialEdgeCandidates(
            vertical: Self.supported(vertical, alongVertical: true),
            horizontal: Self.supported(horizontal, alongVertical: false)
        )
    }

    private static func supported(_ points: [SIMD3<Float>], alongVertical: Bool) -> [SIMD3<Float>] {
        guard points.count >= 3 else { return [] }
        let transverseTolerance: Float = 0.045
        let minAlong: Float = 0.025
        let maxAlong: Float = 0.30
        return points.filter { p in
            points.contains { q in
                let dy = abs(q.y - p.y)
                let dxz = hypot(q.x - p.x, q.z - p.z)
                if alongVertical {
                    return dy >= minAlong && dy <= maxAlong && dxz <= transverseTolerance
                } else {
                    return dxz >= minAlong && dxz <= maxAlong && dy <= transverseTolerance
                }
            }
        }
    }
}

enum DepthSweepSampler {
    static func sampleWorldEdgeCandidates(
        frame: ARFrame,
        stridePixels: Int = 8,
        minimumDepthJumpMetres: Float = 0.025,
        centreCropFraction: Float = 0.72
    ) -> PartialEdgeCandidates? {
        guard let depth = frame.sceneDepth else { return nil }

        let depthMap = depth.depthMap
        let confidenceMap = depth.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap { CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let rowStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
        let values = depthBase.assumingMemoryBound(to: Float32.self)

        var confidenceValues: UnsafeMutablePointer<UInt8>?
        var confidenceStride = 0
        if let confidenceMap, let base = CVPixelBufferGetBaseAddress(confidenceMap) {
            confidenceValues = base.assumingMemoryBound(to: UInt8.self)
            confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
        }

        let imageResolution = frame.camera.imageResolution
        let sx = Float(width) / Float(imageResolution.width)
        let sy = Float(height) / Float(imageResolution.height)
        var intr = frame.camera.intrinsics
        intr.columns.0.x *= sx
        intr.columns.1.y *= sy
        intr.columns.2.x *= sx
        intr.columns.2.y *= sy

        func validDepth(_ x: Int, _ y: Int) -> Float? {
            guard x >= 0, x < width, y >= 0, y < height else { return nil }
            if let confidenceValues, confidenceStride > 0 {
                guard confidenceValues[y * confidenceStride + x] >= 1 else { return nil }
            }
            let d = values[y * rowStride + x]
            guard d.isFinite, d > 0.15, d < 6.0 else { return nil }
            return d
        }

        func worldPoint(x: Int, y: Int, depthMetres: Float) -> SIMD3<Float>? {
            guard let cameraPoint = DepthBackProjector.cameraPoint(
                pixel: CGPoint(x: x, y: y), depthMetres: depthMetres, intrinsics: intr
            ) else { return nil }
            return DepthBackProjector.worldPoint(
                cameraPoint: cameraPoint, cameraTransform: frame.camera.transform
            )
        }

        var result = PartialEdgeCandidates()
        let step = max(4, stridePixels)
        let crop = max(0.35, min(1.0, centreCropFraction))
        let marginX = Int(Float(width) * (1.0 - crop) * 0.5)
        let marginY = Int(Float(height) * (1.0 - crop) * 0.5)
        let minX = max(step, marginX)
        let maxX = min(width - step, width - marginX)
        let minY = max(step, marginY)
        let maxY = min(height - step, height - marginY)

        for y in stride(from: minY, to: maxY, by: step) {
            for x in stride(from: minX, to: maxX, by: step) {
                guard
                    let centre = validDepth(x, y),
                    let left = validDepth(x - step, y),
                    let right = validDepth(x + step, y),
                    let up = validDepth(x, y - step),
                    let down = validDepth(x, y + step)
                else { continue }

                let horizontalGradient = abs(right - left)
                let verticalGradient = abs(down - up)
                guard max(horizontalGradient, verticalGradient) >= minimumDepthJumpMetres else { continue }
                guard let world = worldPoint(x: x, y: y, depthMetres: centre) else { continue }

                if horizontalGradient > verticalGradient * 1.25 {
                    result.vertical.append(world)
                } else if verticalGradient > horizontalGradient * 1.25 {
                    result.horizontal.append(world)
                }
            }
        }
        return result
    }
}

struct PartialOpeningMeasurement: Sendable, Equatable {
    let widthMM: Double
    let heightMM: Double
    let verticalPointCount: Int
    let horizontalPointCount: Int
    let confidence: Double
}

/// Fuses local LiDAR depth discontinuities in ARKit world space.
///
/// The important difference from the first prototype is that measurements are
/// no longer derived from image-space left/right/top/bottom labels. We first
/// determine the facade/opening horizontal axis in world space and then look
/// for persistent edge bands. This lets opposite sides be scanned at different
/// times and from different camera poses.
struct PartialOpeningAccumulator {
    private(set) var vertical: [SIMD3<Float>] = []
    private(set) var horizontal: [SIMD3<Float>] = []

    let maxPointsPerClass = 5000
    private let bandWidthMetres: Float = 0.035
    private let minimumBandPoints = 24

    mutating func reset() {
        vertical.removeAll(keepingCapacity: true)
        horizontal.removeAll(keepingCapacity: true)
    }

    mutating func add(_ candidates: PartialEdgeCandidates) {
        vertical.append(contentsOf: candidates.vertical)
        horizontal.append(contentsOf: candidates.horizontal)
        Self.trim(&vertical, maximum: maxPointsPerClass)
        Self.trim(&horizontal, maximum: maxPointsPerClass)
    }

    var measurement: PartialOpeningMeasurement? {
        guard vertical.count >= 120, horizontal.count >= 120 else { return nil }

        let all = vertical + horizontal
        let origin = centroid(all)
        guard let horizontalAxis = dominantHorizontalAxis(points: all, origin: origin) else { return nil }

        let verticalCoordinates = vertical.map { simd_dot($0 - origin, horizontalAxis) }
        let horizontalCoordinates = horizontal.map { $0.y }

        let verticalBands = persistentBands(verticalCoordinates)
        let horizontalBands = persistentBands(horizontalCoordinates)
        guard verticalBands.count >= 2, horizontalBands.count >= 2 else { return nil }

        // Select the most widely separated persistent pair. Sparse clutter can
        // no longer become an outer edge merely because it is an extreme point.
        guard
            let verticalPair = widestSupportedPair(verticalBands),
            let horizontalPair = widestSupportedPair(horizontalBands)
        else { return nil }

        let widthMM = Double(abs(verticalPair.1.centre - verticalPair.0.centre)) * 1000.0
        let heightMM = Double(abs(horizontalPair.1.centre - horizontalPair.0.centre)) * 1000.0
        guard widthMM >= 100, heightMM >= 100 else { return nil }

        let weakestSupport = min(
            min(verticalPair.0.count, verticalPair.1.count),
            min(horizontalPair.0.count, horizontalPair.1.count)
        )
        let confidence = min(1.0, Double(weakestSupport) / 120.0)

        return PartialOpeningMeasurement(
            widthMM: widthMM,
            heightMM: heightMM,
            verticalPointCount: vertical.count,
            horizontalPointCount: horizontal.count,
            confidence: confidence
        )
    }

    private struct Band {
        var centre: Float
        var count: Int
    }

    private func persistentBands(_ coordinates: [Float]) -> [Band] {
        guard !coordinates.isEmpty else { return [] }
        let sorted = coordinates.sorted()
        var groups: [[Float]] = []
        var current: [Float] = [sorted[0]]

        for value in sorted.dropFirst() {
            if value - (current.last ?? value) <= bandWidthMetres {
                current.append(value)
            } else {
                if current.count >= minimumBandPoints { groups.append(current) }
                current = [value]
            }
        }
        if current.count >= minimumBandPoints { groups.append(current) }

        return groups.map { values in
            Band(
                centre: values.reduce(0, +) / Float(values.count),
                count: values.count
            )
        }
    }

    private func widestSupportedPair(_ bands: [Band]) -> (Band, Band)? {
        guard bands.count >= 2 else { return nil }
        var best: (Band, Band)?
        var bestDistance: Float = 0

        for i in 0..<(bands.count - 1) {
            for j in (i + 1)..<bands.count {
                let distance = abs(bands[j].centre - bands[i].centre)
                if distance > bestDistance {
                    bestDistance = distance
                    best = (bands[i], bands[j])
                }
            }
        }
        return best
    }

    private func dominantHorizontalAxis(points: [SIMD3<Float>], origin: SIMD3<Float>) -> SIMD3<Float>? {
        var xx: Float = 0
        var xz: Float = 0
        var zz: Float = 0

        for p in points {
            let x = p.x - origin.x
            let z = p.z - origin.z
            xx += x * x
            xz += x * z
            zz += z * z
        }

        let angle = 0.5 * atan2(2 * xz, xx - zz)
        let axis = SIMD3<Float>(cos(angle), 0, sin(angle))
        let length = simd_length(axis)
        guard length > 0.001 else { return nil }
        return axis / length
    }

    private func centroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return SIMD3<Float>(repeating: 0) }
        return points.reduce(SIMD3<Float>(repeating: 0), +) / Float(points.count)
    }

    private static func trim(_ points: inout [SIMD3<Float>], maximum: Int) {
        guard points.count > maximum else { return }
        points.removeFirst(points.count - maximum)
    }
}
