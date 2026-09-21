import simd
import XCTest
@testable import Sparingsmeter

final class Opening3DAccumulatorTests: XCTestCase {
    func testSyntheticRectangleProducesExpectedSize() {
        var acc = Opening3DAccumulator()

        var clouds = EdgePointClouds()
        let width: Float = 1.250
        let height: Float = 2.200
        let z: Float = -1.5

        for i in 0..<40 {
            let t = Float(i) / 39.0
            clouds.left.append(SIMD3<Float>(0, t * height, z))
            clouds.right.append(SIMD3<Float>(width, t * height, z))
            clouds.bottom.append(SIMD3<Float>(t * width, 0, z))
            clouds.top.append(SIMD3<Float>(t * width, height, z))
        }

        acc.add(clouds)

        let m = acc.measurement
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.widthMM ?? 0, 1250, accuracy: 1.0)
        XCTAssertEqual(m?.heightMM ?? 0, 2200, accuracy: 1.0)
    }
}
