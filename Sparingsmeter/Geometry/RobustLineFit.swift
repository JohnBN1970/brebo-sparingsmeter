import Foundation
import simd

struct Line3D: Sendable, Equatable {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    let rmsResidualMM: Double
    let pointCount: Int
}

/// Eerste robuuste lijnfit voor sparingsranden.
/// De richting volgt uit PCA op de 3D-punten.
/// Extreme uitschieters worden op residu gefilterd en daarna wordt opnieuw gefit.
enum RobustLineFit {
    static func fit(
        points: [SIMD3<Float>],
        outlierThresholdMM: Double = 8.0
    ) -> Line3D? {
        guard points.count >= 6 else { return nil }

        guard let first = pcaFit(points: points) else { return nil }

        let thresholdM = Float(outlierThresholdMM / 1000.0)
        let filtered = points.filter {
            perpendicularDistance(point: $0, line: first) <= thresholdM
        }

        guard filtered.count >= 6 else { return nil }
        return pcaFit(points: filtered)
    }

    private static func pcaFit(points: [SIMD3<Float>]) -> Line3D? {
        guard points.count >= 2 else { return nil }

        let count = Float(points.count)
        let centroid = points.reduce(SIMD3<Float>(repeating: 0), +) / count

        var covariance = simd_float3x3()
        covariance.columns.0 = SIMD3<Float>(repeating: 0)
        covariance.columns.1 = SIMD3<Float>(repeating: 0)
        covariance.columns.2 = SIMD3<Float>(repeating: 0)

        for point in points {
            let d = point - centroid
            covariance.columns.0 += d * d.x
            covariance.columns.1 += d * d.y
            covariance.columns.2 += d * d.z
        }

        covariance.columns.0 /= count
        covariance.columns.1 /= count
        covariance.columns.2 /= count

        // Power iteration: dominante eigenvector = hoofdrichting.
        var direction = SIMD3<Float>(1, 1, 1)
        direction = simd_normalize(direction)

        for _ in 0..<20 {
            let next = covariance * direction
            let length = simd_length(next)
            guard length > 0.000001 else { return nil }
            direction = next / length
        }

        let residuals = points.map {
            Double(perpendicularDistance(
                point: $0,
                origin: centroid,
                direction: direction
            ))
        }

        let meanSquare = residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count)
        let rmsMM = sqrt(meanSquare) * 1000.0

        return Line3D(
            origin: centroid,
            direction: direction,
            rmsResidualMM: rmsMM,
            pointCount: points.count
        )
    }

    private static func perpendicularDistance(
        point: SIMD3<Float>,
        line: Line3D
    ) -> Float {
        perpendicularDistance(
            point: point,
            origin: line.origin,
            direction: line.direction
        )
    }

    private static func perpendicularDistance(
        point: SIMD3<Float>,
        origin: SIMD3<Float>,
        direction: SIMD3<Float>
    ) -> Float {
        let delta = point - origin
        let projection = simd_dot(delta, direction) * direction
        return simd_length(delta - projection)
    }
}
