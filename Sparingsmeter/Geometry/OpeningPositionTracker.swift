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

        func stable(_ values: [SIMD3<Float>]) -> Bool {
            guard values.count >= minimumLockSamples else { return false }
            let mean = values.reduce(SIMD3<Float>(repeating: 0), +) / Float(values.count)
            let spread = values.map { simd_distance($0, mean) }.max() ?? .greatestFiniteMagnitude
            return spread <= sideToleranceMetres
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
        let left: SIMD3<Float>
        let right: SIMD3<Float>
        let bottom: SIMD3<Float>
        let top: SIMD3<Float>
    }

    private static func sidePositions(_ estimate: OpeningPositionEstimate) -> SidePositions? {
        // PartialOpeningAccumulator emits a fixed semantic order:
        // [left, right, bottom, top]. Track those physical line centres directly
        // in ARKit world space instead of rebuilding a fresh local axis per frame.
        guard estimate.lines.count == 4 else { return nil }
        func centre(_ line: DebugBoundaryLine) -> SIMD3<Float> {
            (line.start + line.end) * 0.5
        }
        return SidePositions(
            left: centre(estimate.lines[0]),
            right: centre(estimate.lines[1]),
            bottom: centre(estimate.lines[2]),
            top: centre(estimate.lines[3])
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
