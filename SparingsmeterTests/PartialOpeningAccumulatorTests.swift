import simd
import XCTest
@testable import Sparingsmeter

final class PartialOpeningAccumulatorTests: XCTestCase {
    func testPartialSweepsCanBeObservedAtDifferentTimes() {
        var accumulator = PartialOpeningAccumulator()

        let width: Float = 1.25
        let height: Float = 2.20
        let z: Float = -1.4

        var firstSweep = PartialEdgeCandidates()
        var secondSweep = PartialEdgeCandidates()

        for i in 0..<60 {
            let t = Float(i) / 59.0
            firstSweep.vertical.append(SIMD3<Float>(0, t * height, z))
            firstSweep.horizontal.append(SIMD3<Float>(t * width, 0, z))

            secondSweep.vertical.append(SIMD3<Float>(width, t * height, z))
            secondSweep.horizontal.append(SIMD3<Float>(t * width, height, z))
        }

        accumulator.add(firstSweep)
        XCTAssertNil(accumulator.measurement)

        accumulator.add(secondSweep)

        let measurement = accumulator.measurement
        XCTAssertNotNil(measurement)
        XCTAssertEqual(measurement?.widthMM ?? 0, 1250, accuracy: 5)
        XCTAssertEqual(measurement?.heightMM ?? 0, 2200, accuracy: 5)
    }
}
