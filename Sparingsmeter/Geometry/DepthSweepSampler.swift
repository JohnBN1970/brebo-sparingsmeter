import ARKit
import CoreGraphics
import CoreVideo
import Foundation
import simd

struct PartialEdgeCandidates: Sendable {
    var vertical: [SIMD3<Float>] = []
    var horizontal: [SIMD3<Float>] = []

    var totalCount: Int { vertical.count + horizontal.count }
}

/// Finds strong depth discontinuities over the complete LiDAR depth image.
///
/// This is deliberately independent of Vision rectangle detection. It allows
/// the operator to scan only a local part of a large/occluded opening and move
/// along it. The candidates are transformed immediately into ARKit world space,
/// so observations from different camera poses can later be fused.
enum DepthSweepSampler {
    static func sampleWorldEdgeCandidates(
        frame: ARFrame,
        stridePixels: Int = 8,
        minimumDepthJumpMetres: Float = 0.025
    ) -> PartialEdgeCandidates? {
        guard let depth = frame.sceneDepth else { return nil }

        let depthMap = depth.depthMap
        let confidenceMap = depth.confidenceMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
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
                pixel: CGPoint(x: x, y: y),
                depthMetres: depthMetres,
                intrinsics: intr
            ) else { return nil }
            return DepthBackProjector.worldPoint(
                cameraPoint: cameraPoint,
                cameraTransform: frame.camera.transform
            )
        }

        var result = PartialEdgeCandidates()
        let step = max(4, stridePixels)

        for y in stride(from: step, to: height - step, by: step) {
            for x in stride(from: step, to: width - step, by: step) {
                guard
                    let centre = validDepth(x, y),
                    let left = validDepth(x - step, y),
                    let right = validDepth(x + step, y),
                    let up = validDepth(x, y - step),
                    let down = validDepth(x, y + step)
                else { continue }

                let horizontalGradient = abs(right - left)
                let verticalGradient = abs(down - up)
                let strongest = max(horizontalGradient, verticalGradient)

                guard strongest >= minimumDepthJumpMetres else { continue }
                guard let world = worldPoint(x: x, y: y, depthMetres: centre) else { continue }

                // Depth changing left/right indicates a mostly vertical image edge.
                // Depth changing up/down indicates a mostly horizontal image edge.
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
}

/// World-space fusion for scans where the complete opening is never visible
/// in a single image. It keeps only depth-edge candidates and estimates the
/// outer pair of vertical/horizontal edge bands with robust percentiles.
struct PartialOpeningAccumulator {
    private(set) var vertical: [SIMD3<Float>] = []
    private(set) var horizontal: [SIMD3<Float>] = []

    let maxPointsPerClass = 4000

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
        guard vertical.count >= 80, horizontal.count >= 80 else { return nil }

        let origin = centroid(vertical + horizontal)
        guard let horizontalAxis = dominantHorizontalAxis(points: vertical + horizontal, origin: origin) else {
            return nil
        }

        let verticalU = vertical.map { simd_dot($0 - origin, horizontalAxis) }.sorted()
        let horizontalV = horizontal.map { $0.y }.sorted()

        // Outer robust bands: enough to ignore isolated clutter but still allow
        // opposite sides to have been observed at completely different times.
        let left = percentile(verticalU, 0.10)
        let right = percentile(verticalU, 0.90)
        let bottom = percentile(horizontalV, 0.10)
        let top = percentile(horizontalV, 0.90)

        let widthMM = Double(abs(right - left)) * 1000.0
        let heightMM = Double(abs(top - bottom)) * 1000.0

        guard widthMM >= 100, heightMM >= 100 else { return nil }

        return PartialOpeningMeasurement(
            widthMM: widthMM,
            heightMM: heightMM,
            verticalPointCount: vertical.count,
            horizontalPointCount: horizontal.count
        )
    }

    private func dominantHorizontalAxis(
        points: [SIMD3<Float>],
        origin: SIMD3<Float>
    ) -> SIMD3<Float>? {
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

    private func percentile(_ sorted: [Float], _ fraction: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let i = max(0, min(sorted.count - 1, Int(round(Float(sorted.count - 1) * fraction))))
        return sorted[i]
    }

    private static func trim(_ points: inout [SIMD3<Float>], maximum: Int) {
        guard points.count > maximum else { return }
        points.removeFirst(points.count - maximum)
    }
}
