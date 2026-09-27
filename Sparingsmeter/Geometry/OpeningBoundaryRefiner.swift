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
        maximumExpansionMetres: Float = 0.60,
        stepMetres: Float = 0.05
    ) -> OpeningBoundaryRefinement {
        guard seed.count == 4 else {
            return OpeningBoundaryRefinement(lines: seed, score: 0, expansionMetres: 0)
        }

        var bestLines = seed
        var bestValidation = OpeningDepthValidator.validate(frame: frame, lines: seed)
        var bestExpansion: Float = 0

        var expansion = stepMetres
        while expansion <= maximumExpansionMetres + 0.001 {
            let candidate = expanded(seed, by: expansion)
            let validation = OpeningDepthValidator.validate(frame: frame, lines: candidate)

            // Prefer a higher opening score. For equal scores, prefer the
            // smaller outward move so the rectangle cannot run away.
            if validation.score > bestValidation.score + 0.04 {
                bestValidation = validation
                bestLines = candidate
                bestExpansion = expansion
            }

            expansion += stepMetres
        }

        return OpeningBoundaryRefinement(
            lines: bestLines,
            score: bestValidation.score,
            expansionMetres: bestExpansion
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

        let lowY = min(bottom.start.y, bottom.end.y, top.start.y, top.end.y)
        let highY = max(bottom.start.y, bottom.end.y, top.start.y, top.end.y)

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
