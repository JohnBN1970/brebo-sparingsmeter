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
        var found = SIMD4<Bool>(repeating: false)
        var evidenceScores = SIMD4<Double>(repeating: 0)
        var currentLines = seed
        var currentValidation = OpeningDepthValidator.validate(frame: frame, lines: currentLines)

        // Each side searches independently. A side is allowed to move the
        // rectangle only when a repeatable physical transition was actually
        // found. Reaching the 300 mm search limit is a failure, not a distance.
        for side in 0..<4 {
            let baseDistance = distances[side]
            let baseLines = currentLines
            let baseValidation = currentValidation

            var previousScore = currentValidation.score
            var consecutiveEvidence = 0
            var bestEvidenceScore = 0.0
            var sideFound = false

            while distances[side] + stepMetres <= maximumExpansionMetres + 0.001 {
                var trialDistances = distances
                trialDistances[side] += stepMetres
                let candidate = adjusted(
                    seed,
                    left: trialDistances.x,
                    right: trialDistances.y,
                    bottom: trialDistances.z,
                    top: trialDistances.w
                )
                let validation = OpeningDepthValidator.validate(frame: frame, lines: candidate)
                let gain = validation.score - previousScore

                if gain >= 0.04 {
                    consecutiveEvidence += 1
                    bestEvidenceScore = max(bestEvidenceScore, min(1.0, gain / 0.12))
                } else if validation.isOpening {
                    consecutiveEvidence += 1
                    bestEvidenceScore = max(bestEvidenceScore, validation.score)
                } else if gain < -0.06 {
                    break
                } else {
                    consecutiveEvidence = 0
                }

                distances = trialDistances
                currentLines = candidate
                currentValidation = validation
                previousScore = validation.score

                if consecutiveEvidence >= 2 || validation.score >= 0.70 {
                    sideFound = true
                    bestEvidenceScore = max(bestEvidenceScore, validation.score)
                    break
                }
            }

            if sideFound {
                found[side] = true
                evidenceScores[side] = bestEvidenceScore
            } else {
                // Important: do not publish the search limit as if it were a
                // measured correction. Revert this side completely.
                distances[side] = baseDistance
                currentLines = baseLines
                currentValidation = baseValidation
                evidenceScores[side] = bestEvidenceScore
            }
        }

        return OpeningBoundaryRefinement(
            lines: currentLines,
            score: currentValidation.score,
            expansionMetres: max(distances.x, distances.y, distances.z, distances.w),
            leftMetres: distances.x,
            rightMetres: distances.y,
            topMetres: distances.w,
            bottomMetres: distances.z,
            leftFound: found.x,
            rightFound: found.y,
            topFound: found.w,
            bottomFound: found.z,
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
