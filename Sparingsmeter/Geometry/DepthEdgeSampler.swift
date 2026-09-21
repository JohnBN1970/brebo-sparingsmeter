import ARKit
import CoreGraphics
import CoreVideo
import Foundation
import simd

struct EdgePointClouds: Sendable {
    var left: [SIMD3<Float>] = []
    var right: [SIMD3<Float>] = []
    var top: [SIMD3<Float>] = []
    var bottom: [SIMD3<Float>] = []

    var totalCount: Int {
        left.count + right.count + top.count + bottom.count
    }
}

enum DepthEdgeSampler {
    static func sampleWorldPoints(
        tracked: TrackedOpening,
        frame: ARFrame,
        samplesPerEdge: Int = 28
    ) -> EdgePointClouds? {
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

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
        let depthValues = depthBase.assumingMemoryBound(to: Float32.self)

        var confidenceValues: UnsafeMutablePointer<UInt8>?
        var confidenceStride = 0
        if let confidenceMap, let base = CVPixelBufferGetBaseAddress(confidenceMap) {
            confidenceValues = base.assumingMemoryBound(to: UInt8.self)
            confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
        }

        let imageResolution = frame.camera.imageResolution
        let sx = Float(depthWidth) / Float(imageResolution.width)
        let sy = Float(depthHeight) / Float(imageResolution.height)

        let intr = frame.camera.intrinsics
        var depthIntr = intr
        depthIntr.columns.0.x *= sx
        depthIntr.columns.1.y *= sy
        depthIntr.columns.2.x *= sx
        depthIntr.columns.2.y *= sy

        func visionToDepthPixel(_ p: CGPoint) -> CGPoint {
            // Vision origin is bottom-left. Camera/depth pixel origin is top-left.
            let x = p.x * CGFloat(depthWidth - 1)
            let y = (1.0 - p.y) * CGFloat(depthHeight - 1)
            return CGPoint(x: x, y: y)
        }

        func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t,
                    y: a.y + (b.y - a.y) * t)
        }

        func pointAt(_ p: CGPoint) -> SIMD3<Float>? {
            let px = max(0, min(depthWidth - 1, Int(round(p.x))))
            let py = max(0, min(depthHeight - 1, Int(round(p.y))))

            if let confidenceValues, confidenceStride > 0 {
                let confidence = confidenceValues[py * confidenceStride + px]
                // ARConfidenceLevel: low=0, medium=1, high=2.
                guard confidence >= 1 else { return nil }
            }

            let d = depthValues[py * depthStride + px]
            guard d.isFinite, d > 0.15, d < 8.0 else { return nil }

            guard let cameraPoint = DepthBackProjector.cameraPoint(
                pixel: CGPoint(x: px, y: py),
                depthMetres: d,
                intrinsics: depthIntr
            ) else { return nil }

            return DepthBackProjector.worldPoint(
                cameraPoint: cameraPoint,
                cameraTransform: frame.camera.transform
            )
        }

        func sampleEdge(_ a: CGPoint, _ b: CGPoint) -> [SIMD3<Float>] {
            guard samplesPerEdge >= 2 else { return [] }
            let da = visionToDepthPixel(a)
            let db = visionToDepthPixel(b)

            return (0..<samplesPerEdge).compactMap { index in
                let t = CGFloat(index) / CGFloat(samplesPerEdge - 1)
                return pointAt(interpolate(da, db, t))
            }
        }

        return EdgePointClouds(
            left: sampleEdge(tracked.bottomLeft, tracked.topLeft),
            right: sampleEdge(tracked.bottomRight, tracked.topRight),
            top: sampleEdge(tracked.topLeft, tracked.topRight),
            bottom: sampleEdge(tracked.bottomLeft, tracked.bottomRight)
        )
    }
}
