import Foundation

struct OpeningSection: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    /// 0...1 positie over hoogte/breedte.
    let normalizedPosition: Double
    let freeSize: MeasuredValue

    init(id: UUID = UUID(), normalizedPosition: Double, freeSize: MeasuredValue) {
        self.id = id
        self.normalizedPosition = normalizedPosition
        self.freeSize = freeSize
    }
}

struct OpeningGeometry: Codable, Sendable, Equatable {
    var widthSections: [OpeningSection] = []
    var heightSections: [OpeningSection] = []

    var governingFreeWidthMM: Double? {
        widthSections.map(\.freeSize.millimetres).min()
    }

    var governingFreeHeightMM: Double? {
        heightSections.map(\.freeSize.millimetres).min()
    }

    var worstUncertaintyMM: Double? {
        let all = widthSections.map(\.freeSize.uncertaintyMillimetres)
            + heightSections.map(\.freeSize.uncertaintyMillimetres)
        return all.max()
    }

    var productionSize: ProductionSize? {
        guard
            let width = governingFreeWidthMM,
            let height = governingFreeHeightMM,
            let uncertainty = worstUncertaintyMM,
            uncertainty <= MeasurementRules.maximumMeasurementDeviationMM
        else {
            return nil
        }

        return ProductionSize(
            widthMM: width - MeasurementRules.totalClearancePerAxisMM,
            heightMM: height - MeasurementRules.totalClearancePerAxisMM,
            clearancePerSideMM: MeasurementRules.clearancePerSideMM,
            governingUncertaintyMM: uncertainty
        )
    }
}

struct ProductionSize: Codable, Sendable, Equatable {
    let widthMM: Double
    let heightMM: Double
    let clearancePerSideMM: Double
    let governingUncertaintyMM: Double
}
