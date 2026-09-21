import XCTest
@testable import Sparingsmeter

final class MeasurementRulesTests: XCTestCase {
    func testFiveMillimetresPerSideMeansTenPerAxis() {
        XCTAssertEqual(MeasurementRules.clearancePerSideMM, 5)
        XCTAssertEqual(MeasurementRules.totalClearancePerAxisMM, 10)
    }

    func testGoverningMinimumDimensionIsUsed() {
        let geometry = OpeningGeometry(
            widthSections: [
                .init(normalizedPosition: 0.0, freeSize: .init(millimetres: 1252, uncertaintyMillimetres: 1.2, source: .calculated)),
                .init(normalizedPosition: 0.5, freeSize: .init(millimetres: 1249, uncertaintyMillimetres: 1.2, source: .calculated)),
                .init(normalizedPosition: 1.0, freeSize: .init(millimetres: 1246, uncertaintyMillimetres: 1.2, source: .calculated))
            ],
            heightSections: [
                .init(normalizedPosition: 0.0, freeSize: .init(millimetres: 2212, uncertaintyMillimetres: 1.2, source: .calculated)),
                .init(normalizedPosition: 1.0, freeSize: .init(millimetres: 2208, uncertaintyMillimetres: 1.2, source: .calculated))
            ]
        )

        XCTAssertEqual(geometry.productionSize?.widthMM, 1236)
        XCTAssertEqual(geometry.productionSize?.heightMM, 2198)
    }

    func testProductionSizeIsBlockedAboveTwoMillimetresUncertainty() {
        let geometry = OpeningGeometry(
            widthSections: [
                .init(normalizedPosition: 0.5, freeSize: .init(millimetres: 1250, uncertaintyMillimetres: 2.1, source: .calculated))
            ],
            heightSections: [
                .init(normalizedPosition: 0.5, freeSize: .init(millimetres: 2200, uncertaintyMillimetres: 1.0, source: .calculated))
            ]
        )

        XCTAssertNil(geometry.productionSize)
    }
}
