import ARKit
import Foundation
import simd

struct OpeningBoundaryRefinement: Sendable, Equatable {
    let lines: [DebugBoundaryLine]
    let score: Double
    let expansionMetres: Float
    let leftMetres: Float
    let rightMetres: Float
    let topMetres: Float
    let bottomMetres: Float
    let leftFound: Bool
    let rightFound: Bool
    let topFound: Bool
    let bottomFound: Bool
    let leftEvidence: Double
    let rightEvidence: Double
    let topEvidence: Double
    let bottomEvidence: Double
}

enum OpeningBoundaryRefiner {
    static func refine(
        frame: ARFrame,
        seed: [DebugBoundaryLine],
        maximumExpansionMetres: Float = 0.30,
        stepMetres: Float = 0.01
    ) -> OpeningBoundaryRefinement {
        guard seed.count == 4 else {
            return OpeningBoundaryRefinement(
                lines: seed, score: 0, expansionMetres: 0,
                leftMetres: 0, rightMetres: 0, topMetres: 0, bottomMetres: 0,
                leftFound: false, rightFound: false, topFound: false, bottomFound: false,
                leftEvidence: 0, rightEvidence: 0, topEvidence: 0, bottomEvidence: 0
            )
        }

        var distances = SIMD4<Float>(repeating: 0) // L, R, B, T
        var found = [Bool](repeating: false, count: 4)
        var evidenceScores = SIMD4<Double>(repeating: 0)
        var currentLines = seed
        var currentValidation = OpeningDepthValidator.validate(frame: frame, lines: currentLines)

        // Search every side independently for the strongest local LiDAR
        // depth transition. We no longer infer a physical edge from the global
        // opening-depth score; that score can be 100% while the edge is wrong.
        for side in 0..<4 {
            var bestDistance: Float = 0
            var bestEvidence = OpeningDepthValidator.boundaryEvidence(
                frame: frame, lines: seed, side: side
            )

            var distance = stepMetres
            while distance <= maximumExpansionMetres + 0.001 {
                var trial = SIMD4<Float>(repeating: 0)
                trial[side] = distance
                let candidate = adjusted(
                    seed,
                    left: trial.x,
                    right: trial.y,
                    bottom: trial.z,
                    top: trial.w
                )
                let evidence = OpeningDepthValidator.boundaryEvidence(
                    frame: frame, lines: candidate, side: side
                )
                if evidence > bestEvidence {
                    bestEvidence = evidence
                    bestDistance = distance
                }
                distance += stepMetres
            }

            // Require a clear local depth step. Zero correction is valid when
            // the seed itself is already on the physical boundary.
            if bestEvidence >= 0.55 {
                found[side] = true
                evidenceScores[side] = bestEvidence
                distances[side] = bestDistance
            } else {
                found[side] = false
                evidenceScores[side] = bestEvidence
                distances[side] = 0
            }
        }

        currentLines = adjusted(
            seed,
            left: distances.x,
            right: distances.y,
            bottom: distances.z,
            top: distances.w
        )
        currentValidation = OpeningDepthValidator.validate(frame: frame, lines: currentLines)

        return OpeningBoundaryRefinement(
            lines: currentLines,
            score: currentValidation.score,
            expansionMetres: max(distances.x, distances.y, distances.z, distances.w),
            leftMetres: distances.x,
            rightMetres: distances.y,
            topMetres: distances.w,
            bottomMetres: distances.z,
            leftFound: found[0],
            rightFound: found[1],
            topFound: found[3],
            bottomFound: found[2],
            leftEvidence: evidenceScores.x,
            rightEvidence: evidenceScores.y,
            topEvidence: evidenceScores.w,
            bottomEvidence: evidenceScores.z
        )
    }

    private static func adjusted(
        _ lines: [DebugBoundaryLine],
        left: Float,
        right: Float,
        bottom: Float,
        top: Float
    ) -> [DebugBoundaryLine] {
        let leftLine = lines[0]
        let rightLine = lines[1]
        let bottomLine = lines[2]
        let topLine = lines[3]

        let leftCenter = (leftLine.start + leftLine.end) * 0.5
        let rightCenter = (rightLine.start + rightLine.end) * 0.5

        var horizontal = rightCenter - leftCenter
        horizontal.y = 0
        guard simd_length(horizontal) > 0.05 else { return lines }
        horizontal = simd_normalize(horizontal)

        let lowY = [bottomLine.start.y, bottomLine.end.y].reduce(0, +) * 0.5 - bottom
        let highY = [topLine.start.y, topLine.end.y].reduce(0, +) * 0.5 + top

        let newLeftCenter = leftCenter - horizontal * left
        let newRightCenter = rightCenter + horizontal * right

        func point(_ center: SIMD3<Float>, y: Float) -> SIMD3<Float> {
            SIMD3<Float>(center.x, y, center.z)
        }

        return [
            DebugBoundaryLine(
                start: point(newLeftCenter, y: lowY),
                end: point(newLeftCenter, y: highY)
            ),
            DebugBoundaryLine(
                start: point(newRightCenter, y: lowY),
                end: point(newRightCenter, y: highY)
            ),
            DebugBoundaryLine(
                start: point(newLeftCenter, y: lowY),
                end: point(newRightCenter, y: lowY)
            ),
            DebugBoundaryLine(
                start: point(newLeftCenter, y: highY),
                end: point(newRightCenter, y: highY)
            )
        ]
    }
}
