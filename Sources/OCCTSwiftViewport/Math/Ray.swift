// Ray.swift
// ViewportKit
//
// Ray type with intersection tests and camera ray construction.

import simd

/// A ray with origin and normalized direction.
public struct Ray: Sendable {

    /// Ray origin in world space.
    public var origin: SIMD3<Float>

    /// Normalized ray direction.
    public var direction: SIMD3<Float>

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        self.direction = simd_normalize(direction)
    }

    // MARK: - Camera Ray Construction

    /// Constructs a ray from NDC coordinates through the camera.
    ///
    /// - Parameters:
    ///   - ndc: Normalized device coordinates in `[-1, 1]` (x right, y up).
    ///   - cameraState: Current camera state.
    ///   - aspectRatio: Viewport width / height.
    /// - Returns: A world-space ray.
    public static func fromCamera(
        ndc: SIMD2<Float>,
        cameraState: CameraState,
        aspectRatio: Float
    ) -> Ray {
        let right = cameraState.rightVector
        let up = cameraState.upVector
        let forward = cameraState.viewDirection

        if cameraState.isOrthographic {
            let halfH = cameraState.orthographicScale * 0.5
            let halfW = halfH * aspectRatio
            let offset = right * ndc.x * halfW + up * ndc.y * halfH
            return Ray(origin: cameraState.position + offset, direction: forward)
        } else {
            let fovRad = cameraState.fieldOfView * .pi / 180.0
            let halfH = tan(fovRad * 0.5)
            let halfW = halfH * aspectRatio
            let dir = simd_normalize(forward + right * ndc.x * halfW + up * ndc.y * halfH)
            return Ray(origin: cameraState.position, direction: dir)
        }
    }

    /// Constructs a ray through the view center.
    public static func throughViewCenter(
        cameraState: CameraState,
        aspectRatio: Float
    ) -> Ray {
        fromCamera(ndc: .zero, cameraState: cameraState, aspectRatio: aspectRatio)
    }

    // MARK: - Intersection Tests

    /// Ray-AABB intersection using the slab method.
    ///
    /// - Returns: Distance to entry point, or `nil` on miss.
    ///   Returns `0` if the origin is inside the box.
    public func intersects(_ box: BoundingBox) -> Float? {
        let invDir = SIMD3<Float>(
            direction.x != 0 ? 1.0 / direction.x : .infinity,
            direction.y != 0 ? 1.0 / direction.y : .infinity,
            direction.z != 0 ? 1.0 / direction.z : .infinity
        )

        let t1 = (box.min - origin) * invDir
        let t2 = (box.max - origin) * invDir

        let tMin = simd_min(t1, t2)
        let tMax = simd_max(t1, t2)

        let tEntry = Swift.max(tMin.x, Swift.max(tMin.y, tMin.z))
        let tExit = Swift.min(tMax.x, Swift.min(tMax.y, tMax.z))

        guard tExit >= tEntry, tExit >= 0 else { return nil }

        return Swift.max(tEntry, 0)
    }

    /// Ray-triangle intersection using the Moller-Trumbore algorithm.
    ///
    /// - Parameters:
    ///   - v0: First vertex
    ///   - v1: Second vertex
    ///   - v2: Third vertex
    /// - Returns: Distance to intersection point, or `nil` on miss.
    public func intersectsTriangle(
        v0: SIMD3<Float>,
        v1: SIMD3<Float>,
        v2: SIMD3<Float>
    ) -> Float? {
        let epsilon: Float = 1e-6

        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = simd_cross(direction, edge2)
        let a = simd_dot(edge1, h)

        // Ray is parallel to the triangle
        guard abs(a) > epsilon else { return nil }

        let f = 1.0 / a
        let s = origin - v0
        let u = f * simd_dot(s, h)

        guard u >= 0 && u <= 1 else { return nil }

        let q = simd_cross(s, edge1)
        let v = f * simd_dot(direction, q)

        guard v >= 0 && (u + v) <= 1 else { return nil }

        let t = f * simd_dot(edge2, q)

        guard t > epsilon else { return nil }

        return t
    }
}
