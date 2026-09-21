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
        guard
            let leftLine = RobustLineFit.fit(points: left),
            let rightLine = RobustLineFit.fit(points: right),
            let topLine = RobustLineFit.fit(points: top),
            let bottomLine = RobustLineFit.fit(points: bottom)
        else { return nil }

        // Gravity-aligned ARKit world coordinates make Y vertical.
        // Width is measured in the horizontal XZ plane between the centroids
        // of the two vertical edge clouds.
        let leftCentre = centroid(left)
        let rightCentre = centroid(right)
        let topCentre = centroid(top)
        let bottomCentre = centroid(bottom)

        let horizontalDelta = SIMD2<Float>(
            rightCentre.x - leftCentre.x,
            rightCentre.z - leftCentre.z
        )
        let widthMM = Double(simd_length(horizontalDelta)) * 1000.0
        let heightMM = Double(abs(topCentre.y - bottomCentre.y)) * 1000.0

        let residual = max(
            leftLine.rmsResidualMM,
            rightLine.rmsResidualMM,
            topLine.rmsResidualMM,
            bottomLine.rmsResidualMM
        )

        return LiveOpeningMeasurement(
            widthMM: widthMM,
            heightMM: heightMM,
            fitResidualMM: residual,
            pointCount: left.count + right.count + top.count + bottom.count
        )
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
