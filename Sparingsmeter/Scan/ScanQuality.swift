import Foundation

enum ScanQualityStatus: Equatable, Sendable {
    case insufficientCoverage
    case uncertaintyTooHigh(Double)
    case ready(Double)

    var canReleaseProductionSize: Bool {
        if case .ready = self { return true }
        return false
    }
}

struct ScanQualityEvaluator {
    static func evaluate(
        coverage: Double,
        requiredCoverage: Double = 0.85,
        uncertaintyMM: Double?
    ) -> ScanQualityStatus {
        guard coverage >= requiredCoverage else {
            return .insufficientCoverage
        }

        guard let uncertaintyMM else {
            return .insufficientCoverage
        }

        if uncertaintyMM > MeasurementRules.maximumMeasurementDeviationMM {
            return .uncertaintyTooHigh(uncertaintyMM)
        }

        return .ready(uncertaintyMM)
    }
}
