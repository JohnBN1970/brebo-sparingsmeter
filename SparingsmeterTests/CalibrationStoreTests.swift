import XCTest
@testable import Sparingsmeter

@MainActor
final class CalibrationStoreTests: XCTestCase {
    func testThreeSamplesSolveProfile() {
        let store = CalibrationStore()
        store.add(measuredMM: 499, referenceMM: 500)
        store.add(measuredMM: 998, referenceMM: 1000)
        store.add(measuredMM: 1497, referenceMM: 1500)

        XCTAssertEqual(store.samples.count, 3)
        XCTAssertTrue(store.profile.validationRMSErrorMM.isFinite)
        XCTAssertLessThan(store.profile.validationRMSErrorMM, 0.1)
    }
}
