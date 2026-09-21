import Foundation
import simd

struct CrossSectionMeasurement: Sendable, Equatable {
    let normalizedPosition: Double
    let freeSizeMM: Double
    let uncertaintyMM: Double
}

struct GoverningOpeningResult: Sendable, Equatable {
    let widths: [CrossSectionMeasurement]
    let heights: [CrossSectionMeasurement]

    var minimumWidthMM: Double? { widths.map(\.freeSizeMM).min() }
    var minimumHeightMM: Double? { heights.map(\.freeSizeMM).min() }

    var maximumUncertaintyMM: Double? {
        (widths.map(\.uncertaintyMM) + heights.map(\.uncertaintyMM)).max()
    }

    var productionWidthMM: Double? {
        guard let minimumWidthMM else { return nil }
        return minimumWidthMM - MeasurementRules.totalClearancePerAxisMM
    }

    var productionHeightMM: Double? {
        guard let minimumHeightMM else { return nil }
        return minimumHeightMM - MeasurementRules.totalClearancePerAxisMM
    }
}

/// Derives many horizontal/vertical cross-sections from the four fitted edge lines.
/// This is deliberately separate from raw sensor acquisition.
enum GoverningOpeningGeometry {
    static func calculate(
        left: Line3D,
        right: Line3D,
        top: Line3D,
        bottom: Line3D,
        calibration: CalibrationProfile,
        sectionCount: Int = 11
    ) -> GoverningOpeningResult? {
        guard sectionCount >= 2 else { return nil }

        // We use the fitted edge origins and directions to sample positions.
        // Vertical sections are parameterised between bottom/top Y extents.
        let minY = min(left.origin.y, right.origin.y, bottom.origin.y)
        let maxY = max(left.origin.y, right.origin.y, top.origin.y)
        let minX = min(left.origin.x, bottom.origin.x, top.origin.x)
        let maxX = max(right.origin.x, bottom.origin.x, top.origin.x)

        guard maxY > minY, maxX > minX else { return nil }

        var widths: [CrossSectionMeasurement] = []
        var heights: [CrossSectionMeasurement] = []

        for i in 0..<sectionCount {
            let t = Double(i) / Double(sectionCount - 1)
            let y = Float(Double(minY) + (Double(maxY - minY) * t))
            let x = Float(Double(minX) + (Double(maxX - minX) * t))

            if let lp = pointOnLineAtY(left, y: y),
               let rp = pointOnLineAtY(right, y: y) {
                let delta = SIMD2<Float>(rp.x - lp.x, rp.z - lp.z)
                let raw = Double(simd_length(delta)) * 1000.0
                widths.append(.init(
                    normalizedPosition: t,
                    freeSizeMM: calibration.corrected(mm: raw),
                    uncertaintyMM: max(left.rmsResidualMM, right.rmsResidualMM, calibration.validationRMSErrorMM)
                ))
            }

            if let bp = pointOnLineAtX(bottom, x: x),
               let tp = pointOnLineAtX(top, x: x) {
                let raw = Double(simd_length(tp - bp)) * 1000.0
                heights.append(.init(
                    normalizedPosition: t,
                    freeSizeMM: calibration.corrected(mm: raw),
                    uncertaintyMM: max(top.rmsResidualMM, bottom.rmsResidualMM, calibration.validationRMSErrorMM)
                ))
            }
        }

        guard !widths.isEmpty, !heights.isEmpty else { return nil }
        return GoverningOpeningResult(widths: widths, heights: heights)
    }

    private static func pointOnLineAtY(_ line: Line3D, y: Float) -> SIMD3<Float>? {
        guard abs(line.direction.y) > 0.0001 else { return nil }
        let t = (y - line.origin.y) / line.direction.y
        return line.origin + line.direction * t
    }

    private static func pointOnLineAtX(_ line: Line3D, x: Float) -> SIMD3<Float>? {
        guard abs(line.direction.x) > 0.0001 else { return nil }
        let t = (x - line.origin.x) / line.direction.x
        return line.origin + line.direction * t
    }
}
