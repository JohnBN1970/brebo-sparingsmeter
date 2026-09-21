import CoreGraphics
import simd
import XCTest
@testable import Sparingsmeter

final class GeometryMathTests: XCTestCase {
    func testBackProjectionAtOpticalCentre() {
        let intrinsics = simd_float3x3(
            SIMD3<Float>(1000, 0, 0),
            SIMD3<Float>(0, 1000, 0),
            SIMD3<Float>(500, 400, 1)
        )

        let point = DepthBackProjector.cameraPoint(
            pixel: CGPoint(x: 500, y: 400),
            depthMetres: 2,
            intrinsics: intrinsics
        )

        XCTAssertEqual(point?.x, 0, accuracy: 0.0001)
        XCTAssertEqual(point?.y, 0, accuracy: 0.0001)
        XCTAssertEqual(point?.z, -2, accuracy: 0.0001)
    }

    func testRobustLineFitRejectsOneOutlier() {
        var points: [SIMD3<Float>] = []

        for index in 0..<30 {
            let y = Float(index) * 0.05
            points.append(SIMD3<Float>(0.25, y, -1.2))
        }

        points.append(SIMD3<Float>(0.60, 0.4, -0.7))

        let line = RobustLineFit.fit(points: points)

        XCTAssertNotNil(line)
        XCTAssertGreaterThanOrEqual(line?.pointCount ?? 0, 25)
        XCTAssertLessThan(line?.rmsResidualMM ?? 999, 2.0)
    }
}
