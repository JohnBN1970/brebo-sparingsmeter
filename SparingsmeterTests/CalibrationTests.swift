import XCTest
@testable import Sparingsmeter

final class CalibrationTests: XCTestCase {
    func testAffineCalibrationRecoversScaleAndOffset() {
        let samples = [
            CalibrationSample(measuredMM: 499.0, referenceMM: 500.0),
            CalibrationSample(measuredMM: 998.0, referenceMM: 1000.0),
            CalibrationSample(measuredMM: 1497.0, referenceMM: 1500.0),
            CalibrationSample(measuredMM: 1996.0, referenceMM: 2000.0)
        ]

        let profile = CalibrationSolver.solve(samples: samples)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.corrected(mm: 1247.5) ?? 0, 1250.0, accuracy: 0.05)
        XCTAssertLessThan(profile?.validationRMSErrorMM ?? 999, 0.1)
    }

    func testMetrologyGateRejectsUnvalidatedCalibration() {
        let profile = CalibrationProfile(
            scale: 1,
            offsetMM: 0,
            validationRMSErrorMM: 2.4
        )

        let result = MetrologyGate.evaluate(calibration: profile, geometry: nil)
        XCTAssertFalse(result.accepted)
    }
}
