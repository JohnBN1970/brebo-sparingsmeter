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

    let maxPointsPerEdge = 1200

    mutating func reset() {
        left.removeAll(keepingCapacity: true)
        right.removeAll(keepingCapacity: true)
        top.removeAll(keepingCapacity: true)
        bottom.removeAll(keepingCapacity: true)
    }

    mutating func add(_ clouds: EdgePointClouds) {
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
        // First establish the physical opening plane from all accumulated
        // world-space points. The dimensions are then measured in this local
        // coordinate frame, so camera translation/rotation no longer changes
        // which direction counts as width.
        let all = left + right + top + bottom
        guard all.count >= 32, let frame = localFrame(points: all) else { return nil }

        let projectedLeft = left.map { project($0, frame: frame) }
        let projectedRight = right.map { project($0, frame: frame) }
        let projectedTop = top.map { project($0, frame: frame) }
        let projectedBottom = bottom.map { project($0, frame: frame) }

        guard
            projectedLeft.count >= 8,
            projectedRight.count >= 8,
            projectedTop.count >= 8,
            projectedBottom.count >= 8
        else { return nil }

        // Robust medians prevent a few depth samples on glass/background from
        // dragging a complete edge to the wrong location.
        let leftU = median(projectedLeft.map(\.x))
        let rightU = median(projectedRight.map(\.x))
        let topV = median(projectedTop.map(\.y))
        let bottomV = median(projectedBottom.map(\.y))

        let widthMM = Double(abs(rightU - leftU)) * 1000.0
        let heightMM = Double(abs(topV - bottomV)) * 1000.0

        // Reject collapsed/cross-associated geometry. A window opening cannot
        // sensibly have an edge separation of only a few millimetres.
        guard widthMM >= 100, heightMM >= 100 else { return nil }

        let residualsMM =
            projectedLeft.map { abs($0.x - leftU) * 1000 } +
            projectedRight.map { abs($0.x - rightU) * 1000 } +
            projectedTop.map { abs($0.y - topV) * 1000 } +
            projectedBottom.map { abs($0.y - bottomV) * 1000 }

        let robustResidual = Double(percentile(residualsMM, fraction: 0.68))

        return LiveOpeningMeasurement(
            widthMM: widthMM,
            heightMM: heightMM,
            fitResidualMM: robustResidual,
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

        // ARKit world Y is gravity aligned. Estimate the facade/opening normal
        // only in the horizontal XZ plane. The local horizontal axis is then
        // perpendicular to that normal and vertical remains gravity.
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

        // Principal horizontal direction of the opening point cloud.
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
