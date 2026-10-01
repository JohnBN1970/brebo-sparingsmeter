import ARKit
import CoreVideo
import Foundation
import simd

struct OpeningDepthValidation: Sendable, Equatable {
    let score: Double
    let validSamples: Int
    let deeperSamples: Int
    let isOpening: Bool
}

enum OpeningDepthValidator {

    /// Scores one physical opening edge by comparing LiDAR immediately inside
    /// and outside the candidate line. A real reveal/opening boundary has a
    /// repeatable depth step: inside is deeper, outside stays on the near plane.
    static func boundaryEvidence(
        frame: ARFrame,
        lines: [DebugBoundaryLine],
        side: Int,
        probeOffsetMetres: Float = 0.035,
        minimumStepMetres: Float = 0.045
    ) -> Double {
        guard lines.count == 4, side >= 0, side < 4, let sceneDepth = frame.sceneDepth else { return 0 }

        let depthMap = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return 0 }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let stride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
        let values = base.assumingMemoryBound(to: Float32.self)
        let imageResolution = frame.camera.imageResolution
        let sx = Float(width) / Float(imageResolution.width)
        let sy = Float(height) / Float(imageResolution.height)
        var intr = frame.camera.intrinsics
        intr.columns.0.x *= sx; intr.columns.1.y *= sy
        intr.columns.2.x *= sx; intr.columns.2.y *= sy
        let inverseCamera = simd_inverse(frame.camera.transform)

        func observed(_ world: SIMD3<Float>) -> Float? {
            let camera = inverseCamera * SIMD4<Float>(world.x, world.y, world.z, 1)
            let expected = -camera.z
            guard expected.isFinite, expected > 0.15 else { return nil }
            let px = Int(round(camera.x * intr.columns.0.x / expected + intr.columns.2.x))
            let py = Int(round(camera.y * intr.columns.1.y / expected + intr.columns.2.y))
            guard px >= 1, px < width - 1, py >= 1, py < height - 1 else { return nil }
            var samples: [Float] = []
            for yy in (py - 1)...(py + 1) {
                for xx in (px - 1)...(px + 1) {
                    let d = values[yy * stride + xx]
                    if d.isFinite, d > 0.15, d < 6.0 { samples.append(d) }
                }
            }
            guard !samples.isEmpty else { return nil }
            samples.sort()
            return samples[samples.count / 2]
        }

        let leftCenter = (lines[0].start + lines[0].end) * 0.5
        let rightCenter = (lines[1].start + lines[1].end) * 0.5
        var horizontal = rightCenter - leftCenter
        horizontal.y = 0
        guard simd_length(horizontal) > 0.05 else { return 0 }
        horizontal = simd_normalize(horizontal)
        let vertical = SIMD3<Float>(0, 1, 0)

        // Direction from the candidate boundary toward the opening interior.
        let inward: SIMD3<Float>
        switch side {
        case 0: inward = horizontal       // left -> right
        case 1: inward = -horizontal      // right -> left
        case 2: inward = vertical         // bottom -> up
        default: inward = -vertical       // top -> down
        }

        let line = lines[side]
        let fractions: [Float] = [0.18, 0.32, 0.46, 0.60, 0.74, 0.86]
        var scores: [Double] = []
        for t in fractions {
            let p = simd_mix(line.start, line.end, SIMD3<Float>(repeating: t))
            guard let inside = observed(p + inward * probeOffsetMetres),
                  let outside = observed(p - inward * probeOffsetMetres) else { continue }
            let step = inside - outside
            // Full evidence at ~8 cm depth step; reject reversed/no transition.
            let normalized = max(0.0, min(1.0, Double((step - minimumStepMetres) / 0.035)))
            scores.append(normalized)
        }
        guard scores.count >= 3 else { return 0 }
        scores.sort()
        // Median makes a side robust against glass holes and isolated bad pixels.
        return scores[scores.count / 2]
    }

    /// Verifies that the stable four-line frame surrounds a real depth opening.
    /// Interior samples are projected into the LiDAR depth map. A genuine
    /// opening should contain a meaningful number of samples deeper than the
    /// facade/opening plane itself.
    static func validate(
        frame: ARFrame,
        lines: [DebugBoundaryLine],
        minimumDepthDifferenceMetres: Float = 0.06
    ) -> OpeningDepthValidation {
        guard lines.count == 4, let sceneDepth = frame.sceneDepth else {
            return OpeningDepthValidation(score: 0, validSamples: 0, deeperSamples: 0, isOpening: false)
        }

        // PartialOpeningAccumulator publishes lines in this order:
        // left, right, bottom, top.
        let left = lines[0]
        let right = lines[1]

        let depthMap = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else {
            return OpeningDepthValidation(score: 0, validSamples: 0, deeperSamples: 0, isOpening: false)
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let stride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
        let values = base.assumingMemoryBound(to: Float32.self)

        let imageResolution = frame.camera.imageResolution
        let sx = Float(width) / Float(imageResolution.width)
        let sy = Float(height) / Float(imageResolution.height)
        var intr = frame.camera.intrinsics
        intr.columns.0.x *= sx
        intr.columns.1.y *= sy
        intr.columns.2.x *= sx
        intr.columns.2.y *= sy

        let inverseCamera = simd_inverse(frame.camera.transform)

        func depthPixel(for world: SIMD3<Float>) -> (x: Int, y: Int, expected: Float)? {
            let camera = inverseCamera * SIMD4<Float>(world.x, world.y, world.z, 1)
            let expected = -camera.z
            guard expected.isFinite, expected > 0.15 else { return nil }

            let fx = intr.columns.0.x
            let fy = intr.columns.1.y
            let cx = intr.columns.2.x
            let cy = intr.columns.2.y
            guard fx != 0, fy != 0 else { return nil }

            let px = Int(round(camera.x * fx / expected + cx))
            let py = Int(round(camera.y * fy / expected + cy))
            guard px >= 1, px < width - 1, py >= 1, py < height - 1 else { return nil }
            return (px, py, expected)
        }

        func observedDepth(_ x: Int, _ y: Int) -> Float? {
            // 3x3 median reduces single-pixel LiDAR noise.
            var samples: [Float] = []
            samples.reserveCapacity(9)
            for yy in (y - 1)...(y + 1) {
                for xx in (x - 1)...(x + 1) {
                    let d = values[yy * stride + xx]
                    if d.isFinite, d > 0.15, d < 6.0 { samples.append(d) }
                }
            }
            guard !samples.isEmpty else { return nil }
            samples.sort()
            return samples[samples.count / 2]
        }

        var valid = 0
        var deeper = 0

        // Stay away from the four physical edges; validate the enclosed field.
        let fractions: [Float] = [0.20, 0.35, 0.50, 0.65, 0.80]
        for v in fractions {
            let leftPoint = simd_mix(left.start, left.end, SIMD3<Float>(repeating: v))
            let rightPoint = simd_mix(right.start, right.end, SIMD3<Float>(repeating: v))
            for u in fractions {
                let planePoint = simd_mix(leftPoint, rightPoint, SIMD3<Float>(repeating: u))
                guard let pixel = depthPixel(for: planePoint),
                      let observed = observedDepth(pixel.x, pixel.y) else { continue }

                valid += 1
                if observed - pixel.expected >= minimumDepthDifferenceMetres {
                    deeper += 1
                }
            }
        }

        guard valid >= 8 else {
            return OpeningDepthValidation(score: 0, validSamples: valid, deeperSamples: deeper, isOpening: false)
        }

        let score = Double(deeper) / Double(valid)
        return OpeningDepthValidation(
            score: score,
            validSamples: valid,
            deeperSamples: deeper,
            isOpening: score >= 0.55
        )
    }
}
