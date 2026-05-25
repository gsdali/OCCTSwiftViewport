// GeometryUtils.swift
// OCCTSwiftMetalDemo
//
// Geometry utilities for selection hit-testing.

import simd
import OCCTSwiftViewport

/// Geometry helper functions for sub-body selection.
enum GeometryUtils {

    /// Shortest distance from a point to a line segment.
    static func pointToSegmentDistance(
        point: SIMD3<Float>,
        a: SIMD3<Float>,
        b: SIMD3<Float>
    ) -> Float {
        let ab = b - a
        let ap = point - a
        let lengthSq = simd_dot(ab, ab)
        guard lengthSq > 1e-12 else { return simd_distance(point, a) }

        let t = simd_clamp(simd_dot(ap, ab) / lengthSq, 0, 1)
        let closest = a + ab * t
        return simd_distance(point, closest)
    }

    /// Shortest distance from a point to a polyline (sequence of connected segments).
    static func pointToPolylineDistance(
        point: SIMD3<Float>,
        polyline: [SIMD3<Float>]
    ) -> Float {
        guard polyline.count >= 2 else { return .infinity }
        var minDist: Float = .infinity
        for i in 0..<(polyline.count - 1) {
            let d = pointToSegmentDistance(point: point, a: polyline[i], b: polyline[i + 1])
            minDist = min(minDist, d)
        }
        return minDist
    }

    /// Intersects a ray with a specific triangle from a body's geometry.
    ///
    /// Returns the 3D hit point, or nil if the triangle index is out of range or no intersection.
    static func hitPointOnTriangle(
        ray: Ray,
        body: ViewportBody,
        triangleIndex: Int
    ) -> SIMD3<Float>? {
        let stride = 6
        let baseIndex = triangleIndex * 3
        guard baseIndex + 2 < body.indices.count else { return nil }

        let i0 = Int(body.indices[baseIndex])
        let i1 = Int(body.indices[baseIndex + 1])
        let i2 = Int(body.indices[baseIndex + 2])

        func vertex(_ idx: Int) -> SIMD3<Float> {
            let base = idx * stride
            return SIMD3<Float>(
                body.vertexData[base],
                body.vertexData[base + 1],
                body.vertexData[base + 2]
            )
        }

        let v0 = vertex(i0)
        let v1 = vertex(i1)
        let v2 = vertex(i2)

        guard let t = ray.intersectsTriangle(v0: v0, v1: v1, v2: v2) else { return nil }
        return ray.origin + ray.direction * t
    }
}
