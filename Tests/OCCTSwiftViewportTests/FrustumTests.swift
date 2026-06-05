import Testing
import simd
@testable import OCCTSwiftViewport

@Suite("Frustum culling")
struct FrustumTests {

    /// A view-projection from the default camera (distance 10, looking at origin).
    private static func defaultVP(aspect: Float = 1.0) -> simd_float4x4 {
        let cs = CameraState()
        return cs.projectionMatrix(aspectRatio: aspect, near: 0.01, far: 10000.0) * cs.viewMatrix
    }

    @Test("A box at the look-at point is inside the frustum")
    func boxAtOriginInside() {
        let f = Frustum(viewProjection: Self.defaultVP())
        let box = BoundingBox(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        #expect(f.intersects(box))
    }

    @Test("A box far off to the side is culled")
    func boxFarToSideCulled() {
        let f = Frustum(viewProjection: Self.defaultVP())
        let box = BoundingBox(min: SIMD3(100, 0, 0), max: SIMD3(101, 1, 1))
        #expect(f.intersects(box) == false)
    }

    @Test("A box far behind the look-at (beyond far plane region) off-axis is culled")
    func boxFarBehindCulled() {
        let f = Frustum(viewProjection: Self.defaultVP())
        // Far up and to the side — clearly outside the lateral frustum.
        let box = BoundingBox(min: SIMD3(0, 500, 0), max: SIMD3(1, 501, 1))
        #expect(f.intersects(box) == false)
    }

    @Test("A huge box enclosing the frustum is kept")
    func hugeBoxKept() {
        let f = Frustum(viewProjection: Self.defaultVP())
        let box = BoundingBox(min: SIMD3(-1000, -1000, -1000), max: SIMD3(1000, 1000, 1000))
        #expect(f.intersects(box))
    }

    @Test("A box straddling the frustum edge is conservatively kept")
    func straddlingKept() {
        let f = Frustum(viewProjection: Self.defaultVP())
        // Spans from the centre out past the side — must not be culled.
        let box = BoundingBox(min: SIMD3(-1, -1, -1), max: SIMD3(100, 1, 1))
        #expect(f.intersects(box))
    }

    // MARK: - BoundingBox.transformed

    @Test("Identity transform returns the same box")
    func identityTransform() {
        let box = BoundingBox(min: SIMD3(-1, -2, -3), max: SIMD3(4, 5, 6))
        #expect(box.transformed(by: matrix_identity_float4x4) == box)
    }

    @Test("Translation shifts both corners")
    func translationShifts() {
        let box = BoundingBox(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(10, 20, 30, 1)
        let moved = box.transformed(by: t)
        #expect(moved.min == SIMD3<Float>(9, 19, 29))
        #expect(moved.max == SIMD3<Float>(11, 21, 31))
    }

    @Test("A translated body is culled when its bounds move off-screen")
    func translatedBodyCulled() {
        let f = Frustum(viewProjection: Self.defaultVP())
        let local = BoundingBox(min: SIMD3(-0.5, -0.5, -0.5), max: SIMD3(0.5, 0.5, 0.5))
        // At origin: visible.
        #expect(f.intersects(local.transformed(by: matrix_identity_float4x4)))
        // Translated far to the side: culled.
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(200, 0, 0, 1)
        #expect(f.intersects(local.transformed(by: t)) == false)
    }
}
