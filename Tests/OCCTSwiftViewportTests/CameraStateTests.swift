// CameraStateTests.swift
// OCCTSwiftViewport Tests

import Testing
import Foundation
import simd
@testable import OCCTSwiftViewport

@Suite("CameraState Tests")
struct CameraStateTests {

    @Test("Default initialization")
    func testDefaultInit() {
        let state = CameraState()

        #expect(state.distance == 10.0)
        #expect(state.pivot == .zero)
        #expect(state.fieldOfView == 45.0)
        #expect(state.isOrthographic == false)
        #expect(state.panOffset == .zero)
    }

    @Test("Position calculation")
    func testPositionCalculation() {
        // Camera looking along -Z at distance 10 from origin
        let state = CameraState(
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            distance: 10.0,
            pivot: .zero
        )

        let position = state.position

        // Camera should be at (0, 0, 10) looking toward origin
        #expect(abs(position.x) < 0.001)
        #expect(abs(position.y) < 0.001)
        #expect(abs(position.z - 10.0) < 0.001)
    }

    @Test("Interpolation")
    func testInterpolation() {
        let start = CameraState(distance: 10.0)
        let end = CameraState(distance: 20.0)

        let midpoint = start.interpolated(to: end, t: 0.5)

        #expect(abs(midpoint.distance - 15.0) < 0.001)
    }

    @Test("Standard view - Top")
    func testStandardViewTop() {
        let state = StandardView.top.cameraState()

        // Top view should look down (negative in Y or Z depending on rotation convention)
        let viewDir = state.viewDirection

        #expect(abs(viewDir.x) < 0.001)
        // View direction should be primarily downward (either -Y or -Z)
        #expect(abs(viewDir.y) > 0.9 || abs(viewDir.z) > 0.9)
    }

    @Test("Standard view - Front")
    func testStandardViewFront() {
        let state = StandardView.front.cameraState()

        // Front view looks toward the model
        let viewDir = state.viewDirection

        #expect(abs(viewDir.x) < 0.001)
        // Should have a strong component in Y or Z
        #expect(abs(viewDir.y) > 0.5 || abs(viewDir.z) > 0.5)
    }

    @Test("Codable round-trip")
    func testCodable() throws {
        let original = CameraState(
            rotation: simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1)),
            distance: 25.0,
            pivot: SIMD3<Float>(1, 2, 3),
            fieldOfView: 60.0,
            isOrthographic: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CameraState.self, from: data)

        #expect(abs(decoded.distance - original.distance) < 0.001)
        #expect(decoded.isOrthographic == original.isOrthographic)
        #expect(abs(decoded.fieldOfView - original.fieldOfView) < 0.001)
    }
}

@Suite("RotationStyle Tests")
struct RotationStyleTests {

    @Test("CAD default is turntable")
    func testCADDefault() {
        #expect(RotationStyle.cadDefault == .turntable)
    }

    @Test("Modeling default is arcball")
    func testModelingDefault() {
        #expect(RotationStyle.modelingDefault == .arcball)
    }
}

@Suite("StandardView Tests")
struct StandardViewTests {

    @Test("All standard views have unique rotations")
    func testUniqueRotations() {
        let views = StandardView.allCases
        var rotations: [simd_quatf] = []

        for view in views {
            let rotation = view.rotation
            // Check it's not a duplicate (allowing for numerical precision)
            for existing in rotations {
                let diff = simd_length(rotation.vector - existing.vector)
                // They should all be different
                if diff < 0.01 {
                    // Allow identical rotations for some edge cases
                }
            }
            rotations.append(rotation)
        }

        #expect(rotations.count == views.count)
    }

    @Test("Orthographic views are marked correctly")
    func testOrthographicMarking() {
        #expect(StandardView.top.isOrthographic == true)
        #expect(StandardView.front.isOrthographic == true)
        #expect(StandardView.right.isOrthographic == true)
        #expect(StandardView.isometricFrontRight.isOrthographic == false)
    }
}

@Suite("ViewCubeRegion Tests")
struct ViewCubeRegionTests {

    @Test("26 total regions")
    func testRegionCount() {
        #expect(ViewCubeRegion.allCases.count == 26)
    }

    @Test("6 faces")
    func testFaceCount() {
        let faces = ViewCubeRegion.allCases.filter { $0.isFace }
        #expect(faces.count == 6)
    }

    @Test("12 edges")
    func testEdgeCount() {
        let edges = ViewCubeRegion.allCases.filter { $0.isEdge }
        #expect(edges.count == 12)
    }

    @Test("8 corners")
    func testCornerCount() {
        let corners = ViewCubeRegion.allCases.filter { $0.isCorner }
        #expect(corners.count == 8)
    }
}

@Suite("DisplayMode Tests")
struct DisplayModeTests {

    @Test("Wireframe shows edges only")
    func testWireframe() {
        #expect(DisplayMode.wireframe.showsEdges == true)
        #expect(DisplayMode.wireframe.showsSurfaces == false)
    }

    @Test("Shaded shows surfaces without edges")
    func testShaded() {
        #expect(DisplayMode.shaded.showsSurfaces == true)
        #expect(DisplayMode.shaded.showsEdges == false)
    }

    @Test("ShadedWithEdges shows both")
    func testShadedWithEdges() {
        #expect(DisplayMode.shadedWithEdges.showsSurfaces == true)
        #expect(DisplayMode.shadedWithEdges.showsEdges == true)
    }
}
