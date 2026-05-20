// NormalSmoothingTests.swift
// OCCTSwiftViewport Tests
//
// Crease-aware normal smoothing — including the Int32-overflow guard (issue #30).

import Testing
import simd
@testable import OCCTSwiftViewport

@Suite("Normal smoothing")
struct NormalSmoothingTests {

    /// Builds an interleaved `[px,py,pz, nx,ny,nz]` buffer (stride 6) from positions,
    /// seeding every normal with a placeholder so smoothing has something to overwrite.
    private func interleaved(_ positions: [SIMD3<Float>]) -> [Float] {
        var data: [Float] = []
        data.reserveCapacity(positions.count * 6)
        for p in positions {
            data += [p.x, p.y, p.z, 0, 0, 1]
        }
        return data
    }

    // MARK: - Regression: issue #30 — quantize() must not trap

    @Test("Vertex beyond the ±21,474.8 welding-scale ceiling does not trap")
    func largeCoordinateDoesNotTrap() {
        // 30,000 model units * 1e5 scale ≈ 3e9 > Int32.max (~2.147e9): the old
        // Int32(round(...)) initializer trapped here. Reaching the assertion at all
        // proves the clamp held.
        var data = interleaved([
            SIMD3(30_000, 0, 0),
            SIMD3(30_001, 1, 0),
            SIMD3(30_000, 0, 1),
        ])
        NormalSmoothing.smoothNormals(vertexData: &data, indices: [0, 1, 2])
        #expect(data.count == 18)
    }

    @Test("Non-finite coordinates (NaN / ±inf) do not trap")
    func nonFiniteCoordinatesDoNotTrap() {
        var data = interleaved([
            SIMD3(.nan, 0, 0),
            SIMD3(0, .infinity, 0),
            SIMD3(0, 0, -.infinity),
        ])
        NormalSmoothing.smoothNormals(vertexData: &data, indices: [0, 1, 2])
        #expect(data.count == 18)
    }

    // MARK: - Sanity: in-range smoothing still averages shared normals

    @Test("Coplanar shared vertices average to the shared face normal")
    func coplanarVerticesSmoothToFaceNormal() {
        // Two triangles forming a flat quad in the z=0 plane share the (1,0,0) and
        // (0,1,0) corners. Their face normals are identical (+Z), so the shared
        // vertices should average to a clean +Z normal.
        var data = interleaved([
            SIMD3(0, 0, 0), // 0
            SIMD3(1, 0, 0), // 1 (shared)
            SIMD3(0, 1, 0), // 2 (shared)
            SIMD3(1, 1, 0), // 3
        ])
        NormalSmoothing.smoothNormals(vertexData: &data, indices: [0, 1, 2, 1, 3, 2])

        // Vertex 1's normal (offset 1*6 + 3) should be +Z.
        let n1 = SIMD3<Float>(data[9], data[10], data[11])
        #expect(abs(n1.z - 1) < 1e-5)
        #expect(abs(n1.x) < 1e-5)
        #expect(abs(n1.y) < 1e-5)
    }
}
