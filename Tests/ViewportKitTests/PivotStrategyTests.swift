// PivotStrategyTests.swift
// ViewportKit Tests

import Testing
import simd
@testable import ViewportKit

@Suite("PivotStrategy Tests")
@MainActor
struct PivotStrategyTests {

    @Test("Far zoom returns scene center")
    func testFarZoom() {
        let strategy = PivotStrategy()
        let body = ViewportBody.box(id: "box")

        // Camera far away — distance much greater than bounding box diagonal
        let state = CameraState(distance: 100.0)
        let config = DynamicPivotConfiguration(zoomThreshold: 0.5, blendBand: 0.3)

        let pivot = strategy.computePivot(
            cameraState: state,
            bodies: [body],
            aspectRatio: 1.0,
            config: config
        )

        #expect(pivot != nil)
        if let pivot = pivot {
            let bb = body.boundingBox!
            let center = bb.center
            #expect(abs(pivot.x - center.x) < 0.01)
            #expect(abs(pivot.y - center.y) < 0.01)
            #expect(abs(pivot.z - center.z) < 0.01)
        }
    }

    @Test("Close zoom returns raycast hit")
    func testCloseZoom() {
        let strategy = PivotStrategy()
        let body = ViewportBody.box(id: "box")

        // Camera very close — zoomed in, looking at the box
        let state = CameraState(
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            distance: 0.1,
            pivot: .zero
        )
        let config = DynamicPivotConfiguration(zoomThreshold: 0.5, blendBand: 0.3)

        let pivot = strategy.computePivot(
            cameraState: state,
            bodies: [body],
            aspectRatio: 1.0,
            config: config
        )

        #expect(pivot != nil)
        if let pivot = pivot {
            // Should be near the box surface (not at scene center necessarily,
            // but somewhere on or near the box)
            #expect(abs(pivot.x) < 1.0)
            #expect(abs(pivot.y) < 1.0)
            #expect(abs(pivot.z) <= 0.6)
        }
    }

    @Test("Blend zone returns interpolated point")
    func testBlendZone() {
        let strategy = PivotStrategy()
        let body = ViewportBody.box(id: "box")
        let bb = body.boundingBox!
        let diagonal = bb.diagonalLength

        // Position exactly at the threshold
        let config = DynamicPivotConfiguration(zoomThreshold: 0.5, blendBand: 0.3)
        let state = CameraState(
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            distance: diagonal * 0.5,
            pivot: .zero
        )

        let pivot = strategy.computePivot(
            cameraState: state,
            bodies: [body],
            aspectRatio: 1.0,
            config: config
        )

        #expect(pivot != nil)
    }

    @Test("No visible geometry returns nil")
    func testNoGeometry() {
        let strategy = PivotStrategy()
        let state = CameraState(distance: 10.0)
        let config = DynamicPivotConfiguration()

        let pivot = strategy.computePivot(
            cameraState: state,
            bodies: [],
            aspectRatio: 1.0,
            config: config
        )

        #expect(pivot == nil)
    }

    @Test("Config disabled returns nil")
    func testDisabled() {
        let strategy = PivotStrategy()
        let body = ViewportBody.box(id: "box")
        let state = CameraState(distance: 10.0)
        let config = DynamicPivotConfiguration(isEnabled: false)

        let pivot = strategy.computePivot(
            cameraState: state,
            bodies: [body],
            aspectRatio: 1.0,
            config: config
        )

        #expect(pivot == nil)
    }
}
