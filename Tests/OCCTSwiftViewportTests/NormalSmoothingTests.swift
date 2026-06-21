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

    /// Builds an interleaved buffer from explicit (position, normal) pairs — used to
    /// model the per-vertex normals a real B-rep mesher (OCCT `BRepMesh`) supplies,
    /// which the #81 fix must preserve.
    private func interleaved(_ verts: [(p: SIMD3<Float>, n: SIMD3<Float>)]) -> [Float] {
        var data: [Float] = []
        data.reserveCapacity(verts.count * 6)
        for v in verts {
            data += [v.p.x, v.p.y, v.p.z, v.n.x, v.n.y, v.n.z]
        }
        return data
    }

    private func normalAt(_ d: [Float], _ v: Int) -> SIMD3<Float> {
        SIMD3(d[v * 6 + 3], d[v * 6 + 4], d[v * 6 + 5])
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

    // MARK: - Crease preservation (justifies auto-applying — #48 part 2)

    /// Two triangles meeting at a 90° ridge along the shared y-axis edge. With a
    /// crease angle below 90° the edge stays SHARP (each side keeps its own face
    /// normal); with a crease angle above 90° the shared-edge normals average.
    @Test("A hard crease is preserved below the crease angle, averaged above it")
    func creasePreservedBelowAngle() {
        // Two faces meeting at a 90° ridge along the shared edge (0,0,0)-(0,1,0):
        // face A in the z=0 plane, face B in the x=0 plane. v0 (face A) and v3
        // (face B) sit at the same position, so smoothing either splits them
        // (sharp) or merges them (smooth) depending on the crease angle.
        // Seed each face's vertices with that face's true normal — the per-vertex normals a
        // real mesher supplies. Face A (z=0 plane) → +Z; face B (x=0 plane) → +X.
        func build() -> [Float] {
            interleaved([
                (SIMD3(0, 0, 0), SIMD3(0, 0, 1)), (SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(1, 0, 0), SIMD3(0, 0, 1)),   // face A
                (SIMD3(0, 0, 0), SIMD3(1, 0, 0)), (SIMD3(0, 1, 0), SIMD3(1, 0, 0)), (SIMD3(0, 0, 1), SIMD3(1, 0, 0)),   // face B
            ])
        }
        let indices: [UInt32] = [0, 1, 2, 3, 4, 5]
        func normal(_ d: [Float], _ v: Int) -> SIMD3<Float> { normalAt(d, v) }

        // Sharp: 45° crease < 90° ridge → the shared-position normals stay split,
        // each axis-aligned to its own face.
        var sharp = build()
        NormalSmoothing.smoothNormals(vertexData: &sharp, indices: indices, creaseAngle: .pi / 4)
        let aSharp = normal(sharp, 0), bSharp = normal(sharp, 3)
        #expect(simd_length(aSharp - bSharp) > 0.5)            // distinct (sharp)
        #expect(abs(simd_length(aSharp) - 1) < 1e-4)           // unit, single-face
        let aSharpComps = [abs(aSharp.x), abs(aSharp.y), abs(aSharp.z)].filter { $0 > 0.3 }
        #expect(aSharpComps.count == 1)                        // axis-aligned

        // Smooth: 120° crease > 90° ridge → both shared-position normals merge to
        // the same blended (two-component) normal.
        var smooth = build()
        NormalSmoothing.smoothNormals(vertexData: &smooth, indices: indices, creaseAngle: 2.094)
        let aSmooth = normal(smooth, 0), bSmooth = normal(smooth, 3)
        #expect(simd_length(aSmooth - bSmooth) < 1e-3)         // merged (same normal)
        let blendComps = [abs(aSmooth.x), abs(aSmooth.y), abs(aSmooth.z)].filter { $0 > 0.3 }
        #expect(blendComps.count >= 2)                         // blended across faces
    }

    // MARK: - #81 — preserve the mesher's per-vertex normals (no brushed striations)

    /// The fix for #81: within a smooth crease group, the assigned normal is the (area-weighted)
    /// average of the INPUT per-vertex normals, NOT a recomputed face-normal average. So smooth
    /// analytic normals from OCCT survive smoothing instead of being replaced by a biased
    /// face-average (the cause of the "brushed" striations on thread flanks).
    @Test("Smooth per-vertex input normals are preserved, not replaced by the face normal (#81)")
    func smoothInputNormalsPreserved() {
        // A flat quad in the z=0 plane (so both face normals are +Z), but every vertex is seeded
        // with a *tilted* smooth normal N — as if these triangles were a patch of a curved surface
        // the mesher gave analytic normals for. The thin triangles echo the anisotropic thread-flank
        // case from #81. The old code would overwrite N with the +Z face normal; the fix keeps N.
        let N = simd_normalize(SIMD3<Float>(0.30, 0.40, 0.866))
        var data = interleaved([
            (SIMD3(0, 0, 0), N), (SIMD3(8, 0, 0), N), (SIMD3(0, 0.4, 0), N),  // thin triangle
            (SIMD3(8, 0, 0), N), (SIMD3(8, 0.4, 0), N), (SIMD3(0, 0.4, 0), N),
        ])
        NormalSmoothing.smoothNormals(vertexData: &data, indices: [0, 1, 2, 3, 4, 5])

        // Every vertex's normal should still be N (the smooth input), not the +Z face normal.
        for v in 0..<6 {
            let n = normalAt(data, v)
            #expect(simd_length(n - N) < 1e-4, "vertex \(v) normal \(n) drifted from input \(N)")
        }
    }

    /// Backward-compatibility: for a flat mesh (each vertex normal == its own face normal, e.g.
    /// imported STL), the area-weighted average of the input vertex normals equals the old
    /// area-weighted face-normal average — so behaviour is unchanged.
    @Test("Flat mesh (vertex normal == face normal) reduces to the face-normal average (#81)")
    func flatInputMatchesFaceNormalAverage() {
        // The two faces from the crease test (A in z=0 → +Z, B in x=0 → +X), each vertex seeded
        // with ITS OWN face normal (flat-shaded input). With a wide crease angle they form one
        // group, so v0/v3 must merge to the equal-area average of the two face normals — i.e. the
        // exact result the old face-normal averaging produced. Equal triangle areas (both 0.5).
        let nA = SIMD3<Float>(0, 0, 1)   // face A normal
        let nB = SIMD3<Float>(1, 0, 0)   // face B normal
        var data = interleaved([
            (SIMD3(0, 0, 0), nA), (SIMD3(0, 1, 0), nA), (SIMD3(1, 0, 0), nA),   // face A (z=0)
            (SIMD3(0, 0, 0), nB), (SIMD3(0, 1, 0), nB), (SIMD3(0, 0, 1), nB),   // face B (x=0)
        ])
        NormalSmoothing.smoothNormals(vertexData: &data, indices: [0, 1, 2, 3, 4, 5], creaseAngle: 2.094)

        let expected = simd_normalize(nA + nB)                 // (0.707, 0, 0.707)
        let merged = normalAt(data, 0)
        #expect(simd_length(merged - expected) < 1e-4, "flat-input merge \(merged) != face avg \(expected)")
        #expect(simd_length(normalAt(data, 3) - expected) < 1e-4)
    }
}
