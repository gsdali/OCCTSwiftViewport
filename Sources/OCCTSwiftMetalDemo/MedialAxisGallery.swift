// MedialAxisGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift MedialAxis (Voronoi skeleton) computation and visualization.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in medial axis gallery showing Voronoi skeleton computation
/// for planar shapes with wall thickness visualization.
enum MedialAxisGallery {

    // MARK: - Rectangle Skeleton

    /// Computes the medial axis of a simple rectangle.
    static func rectangleSkeleton() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a rectangular face
        guard let wire = Wire.rectangle(width: 6, height: 3),
              let rectShape = Shape.face(from: wire, planar: true) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create rectangle")
        }

        // Show the boundary on the XZ plane
        let boundaryPolyline: [SIMD3<Float>] = [
            SIMD3(-3, 0, -1.5), SIMD3(3, 0, -1.5),
            SIMD3(3, 0, 1.5), SIMD3(-3, 0, 1.5), SIMD3(-3, 0, -1.5)
        ]
        bodies.append(ViewportBody(
            id: "mat-rect-boundary",
            vertexData: [],
            indices: [],
            edges: [boundaryPolyline],
            color: SIMD4(0.4, 0.6, 1.0, 1.0)
        ))

        // Compute medial axis
        guard let medialAxis = MedialAxis(of: rectShape) else {
            return Curve2DGallery.GalleryResult(
                bodies: bodies,
                description: "Failed to compute medial axis"
            )
        }

        // Draw skeleton arcs
        let arcPolylines = medialAxis.drawAll()
        let skeletonEdges = arcsToEdges(arcPolylines)

        bodies.append(ViewportBody(
            id: "mat-rect-skeleton",
            vertexData: [],
            indices: [],
            edges: skeletonEdges,
            color: SIMD4(1.0, 0.4, 0.2, 1.0)
        ))

        // Show nodes as spheres with radius = inscribed circle distance
        let nodes = medialAxis.nodes
        for node in nodes {
            let pos = SIMD3<Float>(Float(node.position.x), 0, Float(node.position.y))
            let radius = Float(node.distance) * 0.3 // Scale down for visibility
            if radius > 0.01 {
                bodies.append(makeMarkerSphere(
                    at: pos, radius: max(radius, 0.05),
                    id: "mat-rect-node-\(node.index)",
                    color: SIMD4(1.0, 0.8, 0.2, 0.4)
                ))
            }
        }

        let info = "Min thickness: \(String(format: "%.3f", medialAxis.minThickness))"
        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Rectangle skeleton: boundary (blue), skeleton (orange). \(info)"
        )
    }

    // MARK: - L-Shape Skeleton

    /// Computes the medial axis of an L-shaped profile showing branching skeleton.
    static func lShapeSkeleton() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create an L-shaped profile using polygon wire
        guard let wire = Wire.polygon([
            SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 2),
            SIMD2(2, 2), SIMD2(2, 4), SIMD2(0, 4)
        ], closed: true),
              let lShape = Shape.face(from: wire, planar: true) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create L-shape")
        }

        // Show the boundary on the XZ plane (centered)
        let boundaryPolyline: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(4, 0, 0), SIMD3(4, 0, 2),
            SIMD3(2, 0, 2), SIMD3(2, 0, 4), SIMD3(0, 0, 4), SIMD3(0, 0, 0)
        ].map { SIMD3($0.x - 2, $0.y, $0.z - 2) }

        bodies.append(ViewportBody(
            id: "mat-l-boundary",
            vertexData: [],
            indices: [],
            edges: [boundaryPolyline],
            color: SIMD4(0.4, 0.6, 1.0, 1.0)
        ))

        // Compute medial axis
        guard let medialAxis = MedialAxis(of: lShape) else {
            return Curve2DGallery.GalleryResult(
                bodies: bodies,
                description: "Failed to compute medial axis for L-shape"
            )
        }

        // Draw skeleton arcs with offset to center
        let arcPolylines = medialAxis.drawAll()
        let skeletonEdges = arcsToEdges(arcPolylines, offset: SIMD2(-2, -2))

        bodies.append(ViewportBody(
            id: "mat-l-skeleton",
            vertexData: [],
            indices: [],
            edges: skeletonEdges,
            color: SIMD4(1.0, 0.4, 0.2, 1.0)
        ))

        // Show nodes
        let nodes = medialAxis.nodes
        for node in nodes {
            let pos = SIMD3<Float>(
                Float(node.position.x) - 2, 0,
                Float(node.position.y) - 2
            )
            bodies.append(makeMarkerSphere(
                at: pos, radius: 0.06,
                id: "mat-l-node-\(node.index)",
                color: SIMD4(1.0, 0.8, 0.2, 1.0)
            ))
        }

        let info = "Min thickness: \(String(format: "%.3f", medialAxis.minThickness))"
        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "L-shape skeleton: shows branching. \(info)"
        )
    }

    // MARK: - Thickness Map

    /// Medial axis skeleton colored by wall thickness.
    static func thicknessMap() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a more complex profile — a rectangle with a notch
        guard let wire = Wire.polygon([
            SIMD2(0, 0), SIMD2(6, 0), SIMD2(6, 3),
            SIMD2(4, 3), SIMD2(4, 2), SIMD2(2, 2),
            SIMD2(2, 3), SIMD2(0, 3)
        ], closed: true),
              let shape = Shape.face(from: wire, planar: true) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create profile")
        }

        // Show boundary centered
        let cx: Float = -3, cz: Float = -1.5
        let boundaryPolyline: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(6, 0, 0), SIMD3(6, 0, 3),
            SIMD3(4, 0, 3), SIMD3(4, 0, 2), SIMD3(2, 0, 2),
            SIMD3(2, 0, 3), SIMD3(0, 0, 3), SIMD3(0, 0, 0)
        ].map { SIMD3($0.x + cx, $0.y, $0.z + cz) }

        bodies.append(ViewportBody(
            id: "mat-thick-boundary",
            vertexData: [],
            indices: [],
            edges: [boundaryPolyline],
            color: SIMD4(0.4, 0.6, 1.0, 1.0)
        ))

        // Compute medial axis
        guard let medialAxis = MedialAxis(of: shape) else {
            return Curve2DGallery.GalleryResult(
                bodies: bodies,
                description: "Failed to compute medial axis"
            )
        }

        // Color each arc by wall thickness (sampled at midpoint)
        let arcCount = medialAxis.arcCount
        for arcIdx in 0..<arcCount {
            let arcPts = medialAxis.drawArc(at: arcIdx)
            guard arcPts.count >= 2 else { continue }

            // Sample distance at midpoint
            let dist = medialAxis.distanceToBoundary(arcIndex: arcIdx, parameter: 0.5)
            let minT = medialAxis.minThickness
            let maxT = minT * 3 // Scale for visual range
            let t = Float(max(0, min(1, (dist - minT) / max(maxT - minT, 0.001))))

            // Blue = thick, red = thin
            let color = SIMD4<Float>(1.0 - t, 0.2, t, 1.0)

            let polyline: [SIMD3<Float>] = arcPts.map {
                SIMD3<Float>(Float($0.x) + cx, 0, Float($0.y) + cz)
            }

            bodies.append(ViewportBody(
                id: "mat-thick-arc-\(arcIdx)",
                vertexData: [],
                indices: [],
                edges: [polyline],
                color: color
            ))
        }

        let info = "Min thickness: \(String(format: "%.3f", medialAxis.minThickness))"
        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Thickness map: red = thin, blue = thick. \(info)"
        )
    }

    // MARK: - Custom Profile Skeleton

    /// Demonstrates computing the medial axis for a hand-crafted complex profile.
    static func customProfileSkeleton() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a T-shaped profile
        guard let wire = Wire.polygon([
            SIMD2(0, 0), SIMD2(6, 0), SIMD2(6, 1.5),
            SIMD2(4, 1.5), SIMD2(4, 4), SIMD2(2, 4),
            SIMD2(2, 1.5), SIMD2(0, 1.5)
        ], closed: true),
              let tShape = Shape.face(from: wire, planar: true) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create T-shape")
        }

        // Show boundary centered
        let cx: Float = -3, cz: Float = -2
        let boundaryPolyline: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(6, 0, 0), SIMD3(6, 0, 1.5),
            SIMD3(4, 0, 1.5), SIMD3(4, 0, 4), SIMD3(2, 0, 4),
            SIMD3(2, 0, 1.5), SIMD3(0, 0, 1.5), SIMD3(0, 0, 0)
        ].map { SIMD3($0.x + cx, $0.y, $0.z + cz) }

        bodies.append(ViewportBody(
            id: "mat-custom-boundary",
            vertexData: [],
            indices: [],
            edges: [boundaryPolyline],
            color: SIMD4(0.4, 0.6, 1.0, 1.0)
        ))

        // Compute medial axis
        guard let medialAxis = MedialAxis(of: tShape) else {
            return Curve2DGallery.GalleryResult(
                bodies: bodies,
                description: "Failed to compute medial axis for T-shape"
            )
        }

        // Draw skeleton arcs
        let arcPolylines = medialAxis.drawAll()
        let skeletonEdges = arcsToEdges(arcPolylines, offset: SIMD2(Double(cx), Double(cz)))

        bodies.append(ViewportBody(
            id: "mat-custom-skeleton",
            vertexData: [],
            indices: [],
            edges: skeletonEdges,
            color: SIMD4(1.0, 0.4, 0.2, 1.0)
        ))

        // Show nodes with inscribed circle indicators
        let nodes = medialAxis.nodes
        for node in nodes {
            let pos = SIMD3<Float>(
                Float(node.position.x) + cx, 0,
                Float(node.position.y) + cz
            )
            let radius = Float(node.distance) * 0.25
            if radius > 0.01 {
                bodies.append(makeMarkerSphere(
                    at: pos, radius: max(radius, 0.04),
                    id: "mat-custom-node-\(node.index)",
                    color: SIMD4(1.0, 0.8, 0.2, 0.4)
                ))
            }
        }

        let info = String(format: "Arcs: %d, Nodes: %d, Min thickness: %.3f",
                          medialAxis.arcCount, medialAxis.nodeCount, medialAxis.minThickness)
        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "T-shape skeleton. \(info)"
        )
    }

    // MARK: - Compute from Selected Face

    /// Computes the medial axis of a given shape (from STEP face selection).
    static func computeForShape(_ shape: Shape) -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        guard let medialAxis = MedialAxis(of: shape) else {
            return Curve2DGallery.GalleryResult(
                bodies: [],
                description: "Failed to compute medial axis for selected shape"
            )
        }

        // Draw skeleton arcs
        let arcPolylines = medialAxis.drawAll()
        let skeletonEdges = arcsToEdges(arcPolylines)

        bodies.append(ViewportBody(
            id: "mat-face-skeleton",
            vertexData: [],
            indices: [],
            edges: skeletonEdges,
            color: SIMD4(1.0, 0.4, 0.2, 1.0)
        ))

        let info = String(format: "Arcs: %d, Nodes: %d, Min thickness: %.3f",
                          medialAxis.arcCount, medialAxis.nodeCount, medialAxis.minThickness)
        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Medial axis for selected face. \(info)"
        )
    }

    // MARK: - Helpers

    /// Converts 2D arc polylines to 3D edge polylines on the XZ plane.
    private static func arcsToEdges(
        _ arcPolylines: [[SIMD2<Double>]],
        offset: SIMD2<Double> = .zero
    ) -> [[SIMD3<Float>]] {
        arcPolylines.compactMap { polyline -> [SIMD3<Float>]? in
            let pts: [SIMD3<Float>] = polyline.map {
                SIMD3<Float>(Float($0.x + offset.x), 0, Float($0.y + offset.y))
            }
            return pts.count >= 2 ? pts : nil
        }
    }

    private static func makeMarkerSphere(
        at position: SIMD3<Float>, radius: Float, id: String, color: SIMD4<Float>
    ) -> ViewportBody {
        var sphere = ViewportBody.sphere(
            id: id, radius: radius, segments: 8, rings: 6, color: color
        )
        let stride = 6
        var offsetVerts: [Float] = []
        offsetVerts.reserveCapacity(sphere.vertexData.count)
        for i in Swift.stride(from: 0, to: sphere.vertexData.count, by: stride) {
            offsetVerts.append(sphere.vertexData[i] + position.x)
            offsetVerts.append(sphere.vertexData[i + 1] + position.y)
            offsetVerts.append(sphere.vertexData[i + 2] + position.z)
            offsetVerts.append(sphere.vertexData[i + 3])
            offsetVerts.append(sphere.vertexData[i + 4])
            offsetVerts.append(sphere.vertexData[i + 5])
        }
        sphere.vertexData = offsetVerts
        return sphere
    }
}
