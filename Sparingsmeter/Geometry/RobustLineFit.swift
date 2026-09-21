import Foundation
import simd

struct Line3D: Sendable, Equatable {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    let rmsResidualMM: Double
    let pointCount: Int
}

/// Robuuste lijnfit voor sparingsranden.
/// Eerst wordt met een deterministische RANSAC-achtige selectie de grootste
/// inliergroep gezocht. Daarna volgt een PCA-refit op alleen die inliers.
enum RobustLineFit {
    static func fit(
        points: [SIMD3<Float>],
        outlierThresholdMM: Double = 8.0
    ) -> Line3D? {
        guard points.count >= 6 else { return nil }

        let thresholdM = Float(outlierThresholdMM / 1000.0)

        guard let seed = bestSeedLine(
            points: points,
            thresholdM: thresholdM
        ) else { return nil }

        let inliers = points.filter {
            perpendicularDistance(
                point: $0,
                origin: seed.origin,
                direction: seed.direction
            ) <= thresholdM
        }

        guard inliers.count >= 6 else { return nil }

        // Refit op de volledige inliergroep voor de uiteindelijke lijn.
        guard let refined = pcaFit(points: inliers) else { return nil }

        // Een tweede filterpass voorkomt dat punten die net buiten de verfijnde
        // lijn vallen alsnog de gerapporteerde RMS verslechteren.
        let refinedInliers = inliers.filter {
            perpendicularDistance(point: $0, line: refined) <= thresholdM
        }

        guard refinedInliers.count >= 6 else { return nil }
        return pcaFit(points: refinedInliers)
    }

    private static func bestSeedLine(
        points: [SIMD3<Float>],
        thresholdM: Float
    ) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard points.count >= 2 else { return nil }

        // Maximaal 24 representatieve kandidaten houdt de rekentijd begrensd,
        // ook wanneer de live puntenwolk honderden of duizenden punten bevat.
        let candidateCount = min(24, points.count)
        let candidateIndices: [Int] = (0..<candidateCount).map { i in
            if candidateCount == 1 { return 0 }
            return Int(
                round(
                    Double(i) * Double(points.count - 1)
                    / Double(candidateCount - 1)
                )
            )
        }

        var bestOrigin: SIMD3<Float>?
        var bestDirection: SIMD3<Float>?
        var bestInlierCount = 0
        var bestResidualSum = Float.greatestFiniteMagnitude

        for a in 0..<candidateIndices.count {
            for b in (a + 1)..<candidateIndices.count {
                let p0 = points[candidateIndices[a]]
                let p1 = points[candidateIndices[b]]
                let delta = p1 - p0
                let length = simd_length(delta)

                guard length > 0.001 else { continue }

                let direction = delta / length
                var inlierCount = 0
                var residualSum: Float = 0

                for point in points {
                    let residual = perpendicularDistance(
                        point: point,
                        origin: p0,
                        direction: direction
                    )

                    if residual <= thresholdM {
                        inlierCount += 1
                        residualSum += residual
                    }
                }

                if inlierCount > bestInlierCount ||
                    (inlierCount == bestInlierCount && residualSum < bestResidualSum) {
                    bestInlierCount = inlierCount
                    bestResidualSum = residualSum
                    bestOrigin = p0
                    bestDirection = direction
                }
            }
        }

        guard
            bestInlierCount >= 6,
            let bestOrigin,
            let bestDirection
        else { return nil }

        return (bestOrigin, bestDirection)
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

        let meanSquare = residuals.reduce(0) { $0 + $1 * $1 }
            / Double(residuals.count)
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
