import ARKit
import Foundation
import simd

struct OpeningBoundaryRefinement: Sendable, Equatable {
    let lines: [DebugBoundaryLine]
    let score: Double
    let expansionMetres: Float
}

enum OpeningBoundaryRefiner {
    /// Starting from a stable rectangle, search outward in the same physical
    /// plane. The first goal is not dimensioning: it is to move an internal
    /// stable rectangle toward the outer physical opening boundary.
    static func refine(
        frame: ARFrame,
        seed: [DebugBoundaryLine],
        maximumExpansionMetres: Float = 0.30,
        stepMetres: Float = 0.01
    ) -> OpeningBoundaryRefinement {
        guard seed.count == 4 else {
            return OpeningBoundaryRefinement(lines: seed, score: 0, expansionMetres: 0)
        }

        var currentLines = seed
        var currentValidation = OpeningDepthValidator.validate(frame: frame, lines: seed)
        var totalExpansion: Float = 0
        var previousScore = currentValidation.score
        var consecutiveEvidence = 0

        // Walk outward in small increments and stop at the FIRST sustained
        // depth transition. Do not scan the whole range and pick a distant
        // maximum: that was the cause of the 550 mm overshoot.
        while totalExpansion + stepMetres <= maximumExpansionMetres + 0.001 {
            let candidate = expanded(seed, by: totalExpansion + stepMetres)
            let validation = OpeningDepthValidator.validate(frame: frame, lines: candidate)
            let gain = validation.score - previousScore

            if gain >= 0.04 || validation.isOpening {
                consecutiveEvidence += 1
            } else if gain < -0.06 {
                break
            } else {
                consecutiveEvidence = 0
            }

            currentLines = candidate
            currentValidation = validation
            totalExpansion += stepMetres
            previousScore = validation.score

            // Two adjacent 10 mm steps must agree. This is deliberately
            // conservative; later this becomes independent L/R/B/O search.
            if consecutiveEvidence >= 2 || validation.score >= 0.70 {
                break
            }
        }

        return OpeningBoundaryRefinement(
            lines: currentLines,
            score: currentValidation.score,
            expansionMetres: totalExpansion
        )
    }

    private static func expanded(_ lines: [DebugBoundaryLine], by amount: Float) -> [DebugBoundaryLine] {
        let left = lines[0]
        let right = lines[1]
        let bottom = lines[2]
        let top = lines[3]

        let leftCenter = (left.start + left.end) * 0.5
        let rightCenter = (right.start + right.end) * 0.5
        var horizontal = rightCenter - leftCenter
        horizontal.y = 0
        guard simd_length(horizontal) > 0.05 else { return lines }
        horizontal = simd_normalize(horizontal)

        let lowY = [bottom.start.y, bottom.end.y, top.start.y, top.end.y].min() ?? bottom.start.y
        let highY = [bottom.start.y, bottom.end.y, top.start.y, top.end.y].max() ?? top.start.y

        let newLeftCenter = leftCenter - horizontal * amount
        let newRightCenter = rightCenter + horizontal * amount
        let newLowY = lowY - amount
        let newHighY = highY + amount

        func point(_ center: SIMD3<Float>, y: Float) -> SIMD3<Float> {
            SIMD3<Float>(center.x, y, center.z)
        }

        let newLeft = DebugBoundaryLine(
            start: point(newLeftCenter, y: newLowY),
            end: point(newLeftCenter, y: newHighY)
        )
        let newRight = DebugBoundaryLine(
            start: point(newRightCenter, y: newLowY),
            end: point(newRightCenter, y: newHighY)
        )
        let newBottom = DebugBoundaryLine(
            start: point(newLeftCenter, y: newLowY),
            end: point(newRightCenter, y: newLowY)
        )
        let newTop = DebugBoundaryLine(
            start: point(newLeftCenter, y: newHighY),
            end: point(newRightCenter, y: newHighY)
        )
        return [newLeft, newRight, newBottom, newTop]
    }
}
