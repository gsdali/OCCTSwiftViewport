// RayTests.swift
// ViewportKit Tests

import Testing
import simd
@testable import ViewportKit

@Suite("Ray Tests")
struct RayTests {

    // MARK: - Ray-AABB

    @Test("Ray-AABB hit through center")
    func testAABBHit() {
        let ray = Ray(
            origin: SIMD3<Float>(0, 0, -5),
            direction: SIMD3<Float>(0, 0, 1)
        )
        let box = BoundingBox(
            min: SIMD3<Float>(-1, -1, -1),
            max: SIMD3<Float>(1, 1, 1)
        )

        let t = ray.intersects(box)
        #expect(t != nil)
        if let t = t {
            #expect(abs(t - 4.0) < 0.001)
        }
    }

    @Test("Ray-AABB miss (parallel outside)")
    func testAABBMiss() {
        let ray = Ray(
            origin: SIMD3<Float>(5, 5, -5),
            direction: SIMD3<Float>(0, 0, 1)
        )
        let box = BoundingBox(
            min: SIMD3<Float>(-1, -1, -1),
            max: SIMD3<Float>(1, 1, 1)
        )

        #expect(ray.intersects(box) == nil)
    }

    @Test("Ray-AABB origin inside box returns 0")
    func testAABBOriginInside() {
        let ray = Ray(
            origin: SIMD3<Float>(0, 0, 0),
            direction: SIMD3<Float>(0, 0, 1)
        )
        let box = BoundingBox(
            min: SIMD3<Float>(-1, -1, -1),
            max: SIMD3<Float>(1, 1, 1)
        )

        let t = ray.intersects(box)
        #expect(t != nil)
        if let t = t {
            #expect(abs(t) < 0.001)
        }
    }

    // MARK: - Ray-Triangle

    @Test("Ray-triangle hit (perpendicular)")
    func testTriangleHit() {
        let ray = Ray(
            origin: SIMD3<Float>(0.2, 0.2, -5),
            direction: SIMD3<Float>(0, 0, 1)
        )
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(1, 0, 0)
        let v2 = SIMD3<Float>(0, 1, 0)

        let t = ray.intersectsTriangle(v0: v0, v1: v1, v2: v2)
        #expect(t != nil)
        if let t = t {
            #expect(abs(t - 5.0) < 0.001)
        }
    }

    @Test("Ray-triangle miss (parallel)")
    func testTriangleMissParallel() {
        let ray = Ray(
            origin: SIMD3<Float>(0, 0, -5),
            direction: SIMD3<Float>(1, 0, 0)
        )
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(1, 0, 0)
        let v2 = SIMD3<Float>(0, 1, 0)

        #expect(ray.intersectsTriangle(v0: v0, v1: v1, v2: v2) == nil)
    }

    // MARK: - Camera Ray Construction

    @Test("fromCamera perspective: center ray points along viewDirection")
    func testFromCameraPerspectiveCenter() {
        let state = CameraState(
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            distance: 10.0,
            pivot: .zero,
            isOrthographic: false
        )

        let ray = Ray.fromCamera(ndc: .zero, cameraState: state, aspectRatio: 1.0)
        let viewDir = state.viewDirection

        // Center ray should align with view direction
        let dot = simd_dot(ray.direction, viewDir)
        #expect(dot > 0.999)
    }

    @Test("fromCamera orthographic: all rays have same direction")
    func testFromCameraOrthographic() {
        let state = CameraState(
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            distance: 10.0,
            pivot: .zero,
            orthographicScale: 10.0,
            isOrthographic: true
        )

        let ray1 = Ray.fromCamera(ndc: SIMD2<Float>(-0.5, 0.5), cameraState: state, aspectRatio: 1.0)
        let ray2 = Ray.fromCamera(ndc: SIMD2<Float>(0.5, -0.5), cameraState: state, aspectRatio: 1.0)

        // Directions should be identical (parallel rays)
        let dot = simd_dot(ray1.direction, ray2.direction)
        #expect(dot > 0.999)

        // Origins should differ
        let originDelta = simd_length(ray1.origin - ray2.origin)
        #expect(originDelta > 0.1)
    }
}
