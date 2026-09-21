import Foundation

struct MetrologyGateResult: Sendable, Equatable {
    let accepted: Bool
    let uncertaintyMM: Double
    let reason: String
}

enum MetrologyGate {
    static func evaluate(
        calibration: CalibrationProfile,
        geometry: GoverningOpeningResult?
    ) -> MetrologyGateResult {
        guard calibration.isValidatedForProduction else {
            return .init(
                accepted: false,
                uncertaintyMM: calibration.validationRMSErrorMM,
                reason: "Kalibratie is nog niet gevalideerd binnen +/-2 mm."
            )
        }

        guard let geometry,
              let uncertainty = geometry.maximumUncertaintyMM else {
            return .init(
                accepted: false,
                uncertaintyMM: .infinity,
                reason: "Onvoldoende 3D-geometrie."
            )
        }

        guard uncertainty <= MeasurementRules.maximumMeasurementDeviationMM else {
            return .init(
                accepted: false,
                uncertaintyMM: uncertainty,
                reason: "Meetonzekerheid is groter dan +/-2 mm."
            )
        }

        return .init(
            accepted: true,
            uncertaintyMM: uncertainty,
            reason: "Meting voldoet aan de BREBO meettolerantie."
        )
    }
}
