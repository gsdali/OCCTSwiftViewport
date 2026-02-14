// BoundingBoxTests.swift
// OCCTSwiftViewport Tests

import Testing
import simd
@testable import OCCTSwiftViewport

@Suite("BoundingBox Tests")
struct BoundingBoxTests {

    @Test("Construction from min/max")
    func testConstruction() {
        let bb = BoundingBox(
            min: SIMD3<Float>(-1, -2, -3),
            max: SIMD3<Float>(1, 2, 3)
        )

        #expect(bb.center == SIMD3<Float>(0, 0, 0))
        #expect(bb.size == SIMD3<Float>(2, 4, 6))
        #expect(abs(bb.diagonalLength - simd_length(SIMD3<Float>(2, 4, 6))) < 0.001)
    }

    @Test("ViewportBody.box() has correct bounding box")
    func testBoxBoundingBox() {
        let body = ViewportBody.box(id: "cube")
        let bb = body.boundingBox

        #expect(bb != nil)
        if let bb = bb {
            // Default box is 1x1x1 centered at origin
            #expect(abs(bb.min.x - (-0.5)) < 0.001)
            #expect(abs(bb.min.y - (-0.5)) < 0.001)
            #expect(abs(bb.min.z - (-0.5)) < 0.001)
            #expect(abs(bb.max.x - 0.5) < 0.001)
            #expect(abs(bb.max.y - 0.5) < 0.001)
            #expect(abs(bb.max.z - 0.5) < 0.001)
        }
    }

    @Test("Union of two disjoint boxes")
    func testUnion() {
        let a = BoundingBox(
            min: SIMD3<Float>(0, 0, 0),
            max: SIMD3<Float>(1, 1, 1)
        )
        let b = BoundingBox(
            min: SIMD3<Float>(2, 2, 2),
            max: SIMD3<Float>(3, 3, 3)
        )

        let u = a.union(b)
        #expect(u.min == SIMD3<Float>(0, 0, 0))
        #expect(u.max == SIMD3<Float>(3, 3, 3))
    }

    @Test("Empty vertex data returns nil bounding box")
    func testEmptyVertexData() {
        let body = ViewportBody(
            id: "empty",
            vertexData: [],
            indices: [],
            edges: [],
            color: SIMD4<Float>(1, 1, 1, 1)
        )

        #expect(body.boundingBox == nil)
    }
}
