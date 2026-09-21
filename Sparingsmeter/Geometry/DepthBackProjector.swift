import ARKit
import CoreGraphics
import Foundation
import simd

struct DepthBackProjector {
    /// Projecteert een pixel + diepte terug naar 3D cameraruimte.
    ///
    /// - Parameters:
    ///   - pixel: pixelcoordinaat in het beeld waarop `intrinsics` betrekking heeft.
    ///   - depthMetres: diepte in meters.
    ///   - intrinsics: 3x3 camera intrinsic matrix.
    /// - Returns: 3D punt in cameraruimte, in meters.
    static func cameraPoint(
        pixel: CGPoint,
        depthMetres: Float,
        intrinsics: simd_float3x3
    ) -> SIMD3<Float>? {
        guard depthMetres.isFinite, depthMetres > 0 else { return nil }

        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y

        guard fx != 0, fy != 0 else { return nil }

        let x = (Float(pixel.x) - cx) * depthMetres / fx
        let y = (Float(pixel.y) - cy) * depthMetres / fy

        // ARKit camera kijkt langs -Z.
        return SIMD3<Float>(x, y, -depthMetres)
    }

    static func worldPoint(
        cameraPoint: SIMD3<Float>,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float> {
        let homogeneous = SIMD4<Float>(
            cameraPoint.x,
            cameraPoint.y,
            cameraPoint.z,
            1
        )

        let world = cameraTransform * homogeneous
        return SIMD3<Float>(world.x, world.y, world.z)
    }
}
