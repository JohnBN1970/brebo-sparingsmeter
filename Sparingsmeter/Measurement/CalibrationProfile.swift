import Foundation

struct CalibrationProfile: Codable, Sendable, Equatable {
    /// Multiplicative correction for world-space distances.
    var scale: Double = 1.0

    /// Residual systematic offset in millimetres after scaling.
    var offsetMM: Double = 0.0

    /// Validation residual from known-reference calibration.
    var validationRMSErrorMM: Double = .infinity

    var isValidatedForProduction: Bool {
        validationRMSErrorMM <= MeasurementRules.maximumMeasurementDeviationMM
    }

    func corrected(mm rawMM: Double) -> Double {
        rawMM * scale + offsetMM
    }
}

struct CalibrationSample: Codable, Sendable, Equatable {
    let measuredMM: Double
    let referenceMM: Double
}

enum CalibrationSolver {
    /// Least-squares affine calibration: reference = measured * scale + offset.
    static func solve(samples: [CalibrationSample]) -> CalibrationProfile? {
        guard samples.count >= 3 else { return nil }

        let xs = samples.map(\.measuredMM)
        let ys = samples.map(\.referenceMM)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)

        let numerator = zip(xs, ys).reduce(0.0) { acc, pair in
            acc + (pair.0 - meanX) * (pair.1 - meanY)
        }
        let denominator = xs.reduce(0.0) { acc, x in
            acc + (x - meanX) * (x - meanX)
        }

        guard denominator > 0.000001 else { return nil }

        let scale = numerator / denominator
        let offset = meanY - scale * meanX

        let residuals = zip(xs, ys).map { x, y in
            y - (x * scale + offset)
        }
        let mse = residuals.reduce(0.0) { $0 + $1 * $1 } / Double(residuals.count)
        let rms = sqrt(mse)

        return CalibrationProfile(
            scale: scale,
            offsetMM: offset,
            validationRMSErrorMM: rms
        )
    }
}
