import Foundation

struct MeasuredValue: Codable, Sendable, Equatable {
    let millimetres: Double
    let uncertaintyMillimetres: Double
    let source: MeasurementSource

    var isWithinProductionTolerance: Bool {
        uncertaintyMillimetres <= MeasurementRules.maximumMeasurementDeviationMM
    }
}
