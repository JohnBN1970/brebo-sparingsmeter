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

    mutating func reset() { history.removeAll(keepingCapacity: true) }

    mutating func add(lines: [DebugBoundaryLine]) -> OpeningPositionLock {
        guard let estimate = Self.estimate(from: lines) else { return currentLock }
        history.append(estimate)
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
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

        func stable(_ values: [Float]) -> Bool {
            guard values.count >= minimumLockSamples else { return false }
            return (values.max()! - values.min()!) <= sideToleranceMetres
        }

        let left = stable(canonical.map(\.left))
        let right = stable(canonical.map(\.right))
        let bottom = stable(canonical.map(\.bottom))
        let top = stable(canonical.map(\.top))
        let sides = OpeningSideLocks(left: left, right: right, top: top, bottom: bottom)

        // Progress is now evidence based: each independently stable physical
        // side contributes 25%. There is no global lock before all four agree.
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
        let left: Float
        let right: Float
        let bottom: Float
        let top: Float
    }

    private static func sidePositions(_ estimate: OpeningPositionEstimate) -> SidePositions? {
        guard estimate.lines.count == 4 else { return nil }
        let vertical = estimate.lines.filter {
            abs($0.end.y - $0.start.y) >= hypot($0.end.x - $0.start.x, $0.end.z - $0.start.z)
        }
        let horizontal = estimate.lines.filter {
            abs($0.end.y - $0.start.y) < hypot($0.end.x - $0.start.x, $0.end.z - $0.start.z)
        }
        guard vertical.count == 2, horizontal.count == 2 else { return nil }

        // Use a stable horizontal world axis derived from the two vertical
        // boundary centres; gravity supplies the vertical coordinate.
        let vc = vertical.map { ($0.start + $0.end) * 0.5 }
        var axis = vc[1] - vc[0]
        axis.y = 0
        guard simd_length(axis) > 0.05 else { return nil }
        axis = simd_normalize(axis)
        // Canonical sign prevents left/right swapping between frames.
        if axis.x < 0 || (abs(axis.x) < 0.001 && axis.z < 0) { axis = -axis }

        let origin = estimate.center
        let u = vc.map { simd_dot($0 - origin, axis) }.sorted()
        let hy = horizontal.map { (($0.start.y + $0.end.y) * 0.5) }.sorted()
        return SidePositions(left: u[0], right: u[1], bottom: hy[0], top: hy[1])
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
