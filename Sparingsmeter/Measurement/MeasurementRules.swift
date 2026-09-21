import Foundation

enum MeasurementRules {
    /// Harde BREBO eis: maximaal ±2 mm meetafwijking.
    static let maximumMeasurementDeviationMM: Double = 2.0

    /// Harde BREBO maatvoering: 5 mm aftrek per zijde.
    static let clearancePerSideMM: Double = 5.0

    static let totalClearancePerAxisMM: Double = clearancePerSideMM * 2.0
}
