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

    func testRotatedOpeningKeepsPhysicalDimensions() {
        var acc = Opening3DAccumulator()
        var clouds = EdgePointClouds()

        let width: Float = 1.250
        let height: Float = 2.200
        let angle: Float = 0.72
        let h = SIMD3<Float>(cos(angle), 0, sin(angle))
        let origin = SIMD3<Float>(0.8, 0.35, -2.1)

        func world(_ u: Float, _ v: Float) -> SIMD3<Float> {
            origin + h * u + SIMD3<Float>(0, v, 0)
        }

        for i in 0..<40 {
            let t = Float(i) / 39.0
            clouds.left.append(world(0, t * height))
            clouds.right.append(world(width, t * height))
            clouds.bottom.append(world(t * width, 0))
            clouds.top.append(world(t * width, height))
        }

        acc.add(clouds)

        let m = acc.measurement
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.widthMM ?? 0, 1250, accuracy: 1.0)
        XCTAssertEqual(m?.heightMM ?? 0, 2200, accuracy: 1.0)
    }

    func testCollapsedHeightIsRejected() {
        var acc = Opening3DAccumulator()
        var clouds = EdgePointClouds()

        for i in 0..<40 {
            let t = Float(i) / 39.0
            clouds.left.append(SIMD3<Float>(0, t * 0.009, -1.5))
            clouds.right.append(SIMD3<Float>(1.02, t * 0.009, -1.5))
            clouds.bottom.append(SIMD3<Float>(t * 1.02, 0, -1.5))
            clouds.top.append(SIMD3<Float>(t * 1.02, 0.009, -1.5))
        }

        acc.add(clouds)
        XCTAssertNil(acc.measurement)
    }
}
