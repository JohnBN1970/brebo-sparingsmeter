import Foundation
import simd

struct LiveOpeningMeasurement: Sendable, Equatable {
    let widthMM: Double
    let heightMM: Double
    let fitResidualMM: Double
    let pointCount: Int
}

struct Opening3DAccumulator {
    private(set) var left: [SIMD3<Float>] = []
    private(set) var right: [SIMD3<Float>] = []
    private(set) var top: [SIMD3<Float>] = []
    private(set) var bottom: [SIMD3<Float>] = []

    let maxPointsPerEdge = 1600

    mutating func reset() {
        left.removeAll(keepingCapacity: true)
        right.removeAll(keepingCapacity: true)
        top.removeAll(keepingCapacity: true)
        bottom.removeAll(keepingCapacity: true)
    }

    mutating func add(_ clouds: EdgePointClouds) {
        // L/R/T/B are only candidate labels from Vision. They are retained for
        // diagnostics, but measurement below deliberately rebuilds the physical
        // opening from the combined ARKit world-space cloud.
        left.append(contentsOf: clouds.left)
        right.append(contentsOf: clouds.right)
        top.append(contentsOf: clouds.top)
        bottom.append(contentsOf: clouds.bottom)

        Self.trim(&left, maximum: maxPointsPerEdge)
        Self.trim(&right, maximum: maxPointsPerEdge)
        Self.trim(&top, maximum: maxPointsPerEdge)
        Self.trim(&bottom, maximum: maxPointsPerEdge)
    }

    var measurement: LiveOpeningMeasurement? {
        let all = left + right + top + bottom
        guard all.count >= 80, let frame = localFrame(points: all) else { return nil }

        let uv = all.map { project($0, frame: frame) }
        let us = uv.map(\.x)
        let vs = uv.map(\.y)

        // Reconstruct boundaries from world-space position rather than Vision's
        // image-space side name. Trim the outer 5% to reject glass/background
        // depth spikes, then use narrow boundary bands to estimate each edge.
        let uLo = percentile(us, fraction: 0.05)
        let uHi = percentile(us, fraction: 0.95)
        let vLo = percentile(vs, fraction: 0.05)
        let vHi = percentile(vs, fraction: 0.95)

        guard uHi - uLo > 0.10, vHi - vLo > 0.10 else { return nil }

        let uBand = max(0.025, (uHi - uLo) * 0.10)
        let vBand = max(0.025, (vHi - vLo) * 0.10)

        let leftBand = uv.filter { $0.x <= uLo + uBand }.map(\.x)
        let rightBand = uv.filter { $0.x >= uHi - uBand }.map(\.x)
        let bottomBand = uv.filter { $0.y <= vLo + vBand }.map(\.y)
        let topBand = uv.filter { $0.y >= vHi - vBand }.map(\.y)

        guard
            leftBand.count >= 8, rightBand.count >= 8,
            bottomBand.count >= 8, topBand.count >= 8
        else { return nil }

        let leftU = median(leftBand)
        let rightU = median(rightBand)
        let bottomV = median(bottomBand)
        let topV = median(topBand)

        let widthMM = Double(abs(rightU - leftU)) * 1000.0
        let heightMM = Double(abs(topV - bottomV)) * 1000.0
        guard widthMM >= 100, heightMM >= 100 else { return nil }

        // Boundary spread is diagnostic uncertainty only. The hard +/-2 mm
        // production gate remains closed until physical calibration validates it.
        let residuals =
            leftBand.map { abs($0 - leftU) * 1000 } +
            rightBand.map { abs($0 - rightU) * 1000 } +
            bottomBand.map { abs($0 - bottomV) * 1000 } +
            topBand.map { abs($0 - topV) * 1000 }
        let residual = Double(percentile(residuals, fraction: 0.68))

        return LiveOpeningMeasurement(
            widthMM: widthMM,
            heightMM: heightMM,
            fitResidualMM: residual,
            pointCount: all.count
        )
    }

    private struct LocalFrame {
        let origin: SIMD3<Float>
        let horizontal: SIMD3<Float>
        let vertical: SIMD3<Float>
    }

    private func localFrame(points: [SIMD3<Float>]) -> LocalFrame? {
        let origin = centroid(points)

        // ARKit Y is gravity aligned. PCA in XZ gives the dominant horizontal
        // axis of the accumulated physical opening independent of camera pose.
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
        var horizontal = SIMD3<Float>(cos(angle), 0, sin(angle))
        let length = simd_length(horizontal)
        guard length > 0.001 else { return nil }
        horizontal /= length

        return LocalFrame(
            origin: origin,
            horizontal: horizontal,
            vertical: SIMD3<Float>(0, 1, 0)
        )
    }

    private func project(_ point: SIMD3<Float>, frame: LocalFrame) -> SIMD2<Float> {
        let delta = point - frame.origin
        return SIMD2<Float>(
            simd_dot(delta, frame.horizontal),
            simd_dot(delta, frame.vertical)
        )
    }

    private func centroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return SIMD3<Float>(repeating: 0) }
        return points.reduce(SIMD3<Float>(repeating: 0), +) / Float(points.count)
    }

    private func median(_ values: [Float]) -> Float {
        percentile(values, fraction: 0.5)
    }

    private func percentile(_ values: [Float], fraction: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(round(Float(sorted.count - 1) * fraction))))
        return sorted[index]
    }

    private static func trim(_ points: inout [SIMD3<Float>], maximum: Int) {
        guard points.count > maximum else { return }
        points.removeFirst(points.count - maximum)
    }
}
