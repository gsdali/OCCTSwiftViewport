// SceneRaycastTests.swift
// OCCTSwiftViewport Tests

import Testing
import simd
@testable import OCCTSwiftViewport

@Suite("SceneRaycast Tests")
struct SceneRaycastTests {

    @Test("Hit on a unit box body at known distance")
    func testHitBox() {
        let body = ViewportBody.box(id: "cube")
        let bb = body.boundingBox!
        let cache: [String: BoundingBox] = ["cube": bb]

        // Ray from z = -5 toward origin, should hit front face at z = 0.5
        let ray = Ray(
            origin: SIMD3<Float>(0, 0, -5),
            direction: SIMD3<Float>(0, 0, 1)
        )

        let hit = SceneRaycast.cast(ray: ray, bodies: [body], boundingBoxCache: cache)
        #expect(hit != nil)
        if let hit = hit {
            #expect(hit.bodyID == "cube")
            // Front face of default box is at z = 0.5
            #expect(abs(hit.point.z - (-0.5)) < 0.01)
            #expect(abs(hit.distance - 4.5) < 0.01)
        }
    }

    @Test("Miss returns nil")
    func testMiss() {
        let body = ViewportBody.box(id: "cube")
        let bb = body.boundingBox!
        let cache: [String: BoundingBox] = ["cube": bb]

        // Ray pointing away
        let ray = Ray(
            origin: SIMD3<Float>(10, 10, 10),
            direction: SIMD3<Float>(1, 1, 1)
        )

        let hit = SceneRaycast.cast(ray: ray, bodies: [body], boundingBoxCache: cache)
        #expect(hit == nil)
    }

    @Test("Multiple bodies: returns nearest")
    func testNearest() {
        let near = ViewportBody.box(id: "near")
        let far = ViewportBody(
            id: "far",
            vertexData: shiftedBoxVertexData(z: 5),
            indices: near.indices,
            edges: [],
            color: SIMD4<Float>(1, 0, 0, 1)
        )

        var cache: [String: BoundingBox] = [:]
        cache["near"] = near.boundingBox!
        cache["far"] = far.boundingBox!

        let ray = Ray(
            origin: SIMD3<Float>(0, 0, -10),
            direction: SIMD3<Float>(0, 0, 1)
        )

        let hit = SceneRaycast.cast(ray: ray, bodies: [near, far], boundingBoxCache: cache)
        #expect(hit != nil)
        #expect(hit?.bodyID == "near")
    }

    @Test("Invisible bodies are skipped")
    func testInvisibleSkipped() {
        var body = ViewportBody.box(id: "hidden")
        body.isVisible = false
        let cache: [String: BoundingBox] = ["hidden": body.boundingBox!]

        let ray = Ray(
            origin: SIMD3<Float>(0, 0, -5),
            direction: SIMD3<Float>(0, 0, 1)
        )

        let hit = SceneRaycast.cast(ray: ray, bodies: [body], boundingBoxCache: cache)
        #expect(hit == nil)
    }

    // MARK: - Helpers

    /// Creates vertex data for a unit box shifted along Z.
    private func shiftedBoxVertexData(z: Float) -> [Float] {
        let source = ViewportBody.box(id: "tmp")
        var data = source.vertexData
        let stride = 6
        let vertexCount = data.count / stride
        for i in 0..<vertexCount {
            data[i * stride + 2] += z  // shift position Z
        }
        return data
    }
}
