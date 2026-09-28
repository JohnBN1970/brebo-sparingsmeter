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
                leftMetres: 0, rightMetres: 0, topMetres: 0, bottomMetres: 0
            )
        }

        var distances = SIMD4<Float>(repeating: 0) // L, R, B, T
        var currentLines = seed
        var currentValidation = OpeningDepthValidator.validate(frame: frame, lines: currentLines)

        // Each physical side now searches independently. A side stops at the
        // first sustained improvement in enclosed opening depth instead of
        // dragging all four sides outward together.
        for side in 0..<4 {
            var previousScore = currentValidation.score
            var evidence = 0

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

                if gain >= 0.04 || validation.isOpening {
                    evidence += 1
                } else if gain < -0.06 {
                    break
                } else {
                    evidence = 0
                }

                distances = trialDistances
                currentLines = candidate
                currentValidation = validation
                previousScore = validation.score

                // First repeatable transition wins. This prevents a single side
                // from wandering hundreds of millimetres toward distant clutter.
                if evidence >= 2 || validation.score >= 0.70 {
                    break
                }
            }
        }

        return OpeningBoundaryRefinement(
            lines: currentLines,
            score: currentValidation.score,
            expansionMetres: max(distances.x, distances.y, distances.z, distances.w),
            leftMetres: distances.x,
            rightMetres: distances.y,
            topMetres: distances.w,
            bottomMetres: distances.z
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
