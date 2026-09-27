import Foundation
import simd

struct OpeningSideLocks: Sendable, Equatable {
    let left: Bool
    let right: Bool
    let top: Bool
    let bottom: Bool
    var count: Int { [left, right, top, bottom].filter { $0 }.count }
}

struct OpeningPositionEstimate: Sendable, Equatable {
    let center: SIMD3<Float>
    let width: Float
    let height: Float
    let lines: [DebugBoundaryLine]
}

struct OpeningPositionLock: Sendable, Equatable {
    let progress: Double
    let isLocked: Bool
    let estimate: OpeningPositionEstimate?
    let sides: OpeningSideLocks
}

struct OpeningPositionTracker {
    private var history: [OpeningPositionEstimate] = []
    private let maxHistory = 30
    private let minimumLockSamples = 12
    private let sideToleranceMetres: Float = 0.045

    mutating func reset() {
        history.removeAll(keepingCapacity: true)
    }

    mutating func add(lines: [DebugBoundaryLine]) -> OpeningPositionLock {
        guard let estimate = Self.estimate(from: lines) else { return currentLock }
        history.append(estimate)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        return currentLock
    }

    var currentLock: OpeningPositionLock {
        guard history.count >= 3 else {
            let sides = OpeningSideLocks(left: false, right: false, top: false, bottom: false)
            return OpeningPositionLock(progress: 0, isLocked: false, estimate: history.last, sides: sides)
        }

        let recent = Array(history.suffix(minimumLockSamples))
        let canonical = recent.compactMap(Self.sidePositions)
        guard canonical.count >= 3 else {
            let sides = OpeningSideLocks(left: false, right: false, top: false, bottom: false)
            return OpeningPositionLock(progress: 0, isLocked: false, estimate: history.last, sides: sides)
        }

        func stableXZ(_ values: [SIMD2<Float>]) -> Bool {
            guard values.count >= minimumLockSamples else { return false }
            let mean = values.reduce(SIMD2<Float>(repeating: 0), +) / Float(values.count)
            let spread = values.map { simd_distance($0, mean) }.max() ?? .greatestFiniteMagnitude
            return spread <= sideToleranceMetres
        }

        func stableY(_ values: [Float]) -> Bool {
            guard values.count >= minimumLockSamples else { return false }
            let mean = values.reduce(0, +) / Float(values.count)
            let spread = values.map { abs($0 - mean) }.max() ?? .greatestFiniteMagnitude
            return spread <= sideToleranceMetres
        }

        let left = stableXZ(canonical.map(\.leftXZ))
        let right = stableXZ(canonical.map(\.rightXZ))
        let bottom = stableY(canonical.map(\.bottomY))
        let top = stableY(canonical.map(\.topY))
        let sides = OpeningSideLocks(left: left, right: right, top: top, bottom: bottom)

        // Each physical side contributes 25%. A side is compared only on the
        // coordinate that defines its position:
        // - vertical sides: fixed X/Z position in world space
        // - horizontal sides: fixed world Y height
        // Visible line length may change freely while the operator moves.
        let progress = Double(sides.count) / 4.0
        let locked = sides.count == 4

        return OpeningPositionLock(
            progress: progress,
            isLocked: locked,
            estimate: history.last,
            sides: sides
        )
    }

    private struct SidePositions {
        let leftXZ: SIMD2<Float>
        let rightXZ: SIMD2<Float>
        let bottomY: Float
        let topY: Float
    }

    private static func sidePositions(_ estimate: OpeningPositionEstimate) -> SidePositions? {
        // PartialOpeningAccumulator emits a fixed semantic order:
        // [left, right, bottom, top].
        //
        // Do NOT compare line midpoints in full 3D: the midpoint moves when a
        // partially observed line grows or shrinks. Instead compare only the
        // invariant coordinate that defines the physical line.
        guard estimate.lines.count == 4 else { return nil }

        let left = estimate.lines[0]
        let right = estimate.lines[1]
        let bottom = estimate.lines[2]
        let top = estimate.lines[3]

        let leftXZ = SIMD2<Float>(
            (left.start.x + left.end.x) * 0.5,
            (left.start.z + left.end.z) * 0.5
        )
        let rightXZ = SIMD2<Float>(
            (right.start.x + right.end.x) * 0.5,
            (right.start.z + right.end.z) * 0.5
        )
        let bottomY = (bottom.start.y + bottom.end.y) * 0.5
        let topY = (top.start.y + top.end.y) * 0.5

        return SidePositions(
            leftXZ: leftXZ,
            rightXZ: rightXZ,
            bottomY: bottomY,
            topY: topY
        )
    }

    private static func estimate(from lines: [DebugBoundaryLine]) -> OpeningPositionEstimate? {
        guard lines.count == 4 else { return nil }
        let points = lines.flatMap { [$0.start, $0.end] }
        let center = points.reduce(SIMD3<Float>(repeating: 0), +) / Float(points.count)
        let lengths = lines.map { simd_distance($0.start, $0.end) }.sorted()
        guard lengths.count == 4, lengths[0] > 0.10 else { return nil }

        return OpeningPositionEstimate(
            center: center,
            width: (lengths[0] + lengths[1]) * 0.5,
            height: (lengths[2] + lengths[3]) * 0.5,
            lines: lines
        )
    }
}
