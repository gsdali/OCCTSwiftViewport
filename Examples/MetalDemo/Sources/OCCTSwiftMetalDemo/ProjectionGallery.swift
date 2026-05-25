// ProjectionGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift curve/point projection onto parametric surfaces.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in projection gallery showing 3D curves projected onto surfaces.
enum ProjectionGallery {

    // MARK: - Curve on Cylinder

    /// Projects a helix-like curve onto a cylinder surface.
    static func curveOnCylinder() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a cylinder surface
        guard let cylinder = Surface.cylinder(
            origin: SIMD3(0, 0, 0), axis: SIMD3(0, 0, 1), radius: 2.0
        ) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create cylinder")
        }

        // Show the cylinder as a grid
        if let trimmed = cylinder.trimmed(u1: 0, u2: .pi * 2, v1: -1, v2: 5) {
            bodies.append(contentsOf: surfaceGridBodies(
                trimmed, idPrefix: "proj-cyl", offset: .zero,
                color: SIMD4(0.3, 0.3, 0.5, 0.4)
            ))
        }

        // Create a diagonal line near the cylinder
        guard let curve = Curve3D.segment(
            from: SIMD3(-3, -1, 0),
            to: SIMD3(3, 1, 5)
        ) else {
            return Curve2DGallery.GalleryResult(bodies: bodies, description: "Failed to create curve")
        }

        // Original curve (yellow)
        bodies.append(curveToBody(curve, id: "proj-cyl-orig",
                                  color: SIMD4(1.0, 1.0, 0.2, 1.0)))

        // Project onto cylinder
        if let projected = cylinder.projectCurve3D(curve) {
            bodies.append(curveToBody(projected, id: "proj-cyl-result",
                                      color: SIMD4(1.0, 0.3, 0.3, 1.0)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Curve on cylinder: original (yellow), projected (red)"
        )
    }

    // MARK: - Curve on Sphere

    /// Projects a circle onto a sphere surface.
    static func curveOnSphere() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a sphere surface
        guard let sphere = Surface.sphere(center: SIMD3(0, 0, 0), radius: 3.0) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create sphere")
        }

        // Show the sphere as a grid
        if let trimmed = sphere.trimmed(
            u1: -.pi * 0.9, u2: .pi * 0.9,
            v1: -.pi / 2.5, v2: .pi / 2.5
        ) {
            bodies.append(contentsOf: surfaceGridBodies(
                trimmed, idPrefix: "proj-sph", offset: .zero,
                color: SIMD4(0.3, 0.5, 0.3, 0.4)
            ))
        }

        // Create a tilted circle near the sphere
        guard let circle = Curve3D.circle(
            center: SIMD3(0, 0, 1),
            normal: SIMD3(0.3, 0.3, 1),
            radius: 2.0
        ) else {
            return Curve2DGallery.GalleryResult(bodies: bodies, description: "Failed to create circle")
        }

        // Original circle (cyan)
        bodies.append(curveToBody(circle, id: "proj-sph-orig",
                                  color: SIMD4(0.0, 0.8, 0.9, 1.0)))

        // Project onto sphere
        if let projected = sphere.projectCurve3D(circle) {
            bodies.append(curveToBody(projected, id: "proj-sph-result",
                                      color: SIMD4(1.0, 0.3, 0.3, 1.0)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Curve on sphere: original circle (cyan), projected (red)"
        )
    }

    // MARK: - Composite Projection

    /// Projects a curve that crosses surface boundary — shows multiple UV segments.
    static func compositeProjection() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a BSpline surface
        let poles: [[SIMD3<Double>]] = [
            [SIMD3(-3, -3, 0), SIMD3(0, -3, 2), SIMD3(3, -3, 0)],
            [SIMD3(-3, 0, 1),  SIMD3(0, 0, 3),  SIMD3(3, 0, 1)],
            [SIMD3(-3, 3, 0),  SIMD3(0, 3, 1),  SIMD3(3, 3, 0)],
        ]

        guard let surface = Surface.bezier(poles: poles) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create surface")
        }

        // Show surface grid (dim)
        bodies.append(contentsOf: surfaceGridBodies(
            surface, idPrefix: "proj-comp-surf", offset: .zero,
            color: SIMD4(0.4, 0.4, 0.4, 0.3)
        ))

        // Create a long diagonal curve that spans the surface
        guard let curve = Curve3D.interpolate(points: [
            SIMD3(-4, -4, 2), SIMD3(-1, -1, 3), SIMD3(1, 1, 2), SIMD3(4, 4, 3)
        ]) else {
            return Curve2DGallery.GalleryResult(bodies: bodies, description: "Failed to create curve")
        }

        // Original curve (white)
        bodies.append(curveToBody(curve, id: "proj-comp-orig",
                                  color: SIMD4(0.9, 0.9, 0.9, 1.0)))

        // Project and get segments (different colors)
        let segments = surface.projectCurveSegments(curve)
        let segColors: [SIMD4<Float>] = [
            SIMD4(1.0, 0.3, 0.3, 1.0),  // red
            SIMD4(0.3, 1.0, 0.3, 1.0),  // green
            SIMD4(0.3, 0.3, 1.0, 1.0),  // blue
            SIMD4(1.0, 1.0, 0.3, 1.0),  // yellow
        ]

        for (i, seg) in segments.enumerated() {
            // Convert 2D UV curve back to 3D on the surface for visualization
            let pts2D = seg.drawAdaptive()
            let domain = surface.domain
            var pts3D: [SIMD3<Float>] = []
            for pt in pts2D {
                // Map UV curve points back to surface
                let u = domain.uMin + pt.x * (domain.uMax - domain.uMin)
                let v = domain.vMin + pt.y * (domain.vMax - domain.vMin)
                let p = surface.point(atU: u, v: v)
                pts3D.append(SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)))
            }

            if pts3D.count >= 2 {
                let color = segColors[i % segColors.count]
                bodies.append(ViewportBody(
                    id: "proj-comp-seg-\(i)",
                    vertexData: [],
                    indices: [],
                    edges: [pts3D],
                    color: color
                ))
            }
        }

        // Also try direct 3D projection
        if let projected3D = surface.projectCurve3D(curve) {
            bodies.append(curveToBody(projected3D, id: "proj-comp-3d",
                                      color: SIMD4(1.0, 0.5, 0.0, 0.8)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Composite projection: \(segments.count) UV segments in different colors"
        )
    }

    // MARK: - Point Projection

    /// Scatters points near a surface and shows projection lines colored by distance.
    static func pointProjection() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a curved surface
        let poles: [[SIMD3<Double>]] = [
            [SIMD3(-3, -3, 0), SIMD3(0, -3, 2), SIMD3(3, -3, 0)],
            [SIMD3(-3, 0, 1),  SIMD3(0, 0, 3),  SIMD3(3, 0, 1)],
            [SIMD3(-3, 3, 0),  SIMD3(0, 3, 1),  SIMD3(3, 3, 0)],
        ]

        guard let surface = Surface.bezier(poles: poles) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create surface")
        }

        // Show surface grid
        bodies.append(contentsOf: surfaceGridBodies(
            surface, idPrefix: "proj-pt-surf", offset: .zero,
            color: SIMD4(0.4, 0.4, 0.5, 0.4)
        ))

        // Scatter points above and around the surface
        let pointCount = 20
        var maxDist: Double = 0

        struct ProjResult {
            let original: SIMD3<Double>
            let projected: SIMD3<Double>
            let distance: Double
        }

        var results: [ProjResult] = []

        for i in 0..<pointCount {
            let angle = Double(i) / Double(pointCount) * 2.0 * .pi
            let r = 2.0 + Double.random(in: -0.5...0.5)
            let x = r * cos(angle)
            let y = r * sin(angle)
            let z = 2.0 + Double.random(in: -1.0...2.0)
            let point = SIMD3<Double>(x, y, z)

            if let proj = surface.projectPoint(point) {
                let projPt = surface.point(atU: proj.u, v: proj.v)
                let dist = proj.distance
                maxDist = max(maxDist, dist)
                results.append(ProjResult(original: point, projected: projPt, distance: dist))
            }
        }

        // Render projection lines colored by distance
        for (i, r) in results.enumerated() {
            let t = maxDist > 0 ? Float(r.distance / maxDist) : 0
            // Green = close, Red = far
            let color = SIMD4<Float>(t, 1.0 - t, 0.0, 0.8)

            let orig = SIMD3<Float>(Float(r.original.x), Float(r.original.y), Float(r.original.z))
            let proj = SIMD3<Float>(Float(r.projected.x), Float(r.projected.y), Float(r.projected.z))

            bodies.append(ViewportBody(
                id: "proj-pt-line-\(i)",
                vertexData: [],
                indices: [],
                edges: [[orig, proj]],
                color: color
            ))

            // Small sphere at original point
            bodies.append(makeMarkerSphere(at: orig, radius: 0.08,
                                           id: "proj-pt-sphere-\(i)",
                                           color: color))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Point projection: \(results.count) points, colored green (close) to red (far)"
        )
    }

    // MARK: - Helpers

    private static func curveToBody(
        _ curve: Curve3D, id: String, color: SIMD4<Float>
    ) -> ViewportBody {
        let pts = curve.drawAdaptive()
        let polyline: [SIMD3<Float>] = pts.map {
            SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
        }
        return ViewportBody(
            id: id, vertexData: [], indices: [], edges: [polyline], color: color
        )
    }

    private static func surfaceGridBodies(
        _ surface: Surface,
        idPrefix: String,
        offset: SIMD3<Double>,
        color: SIMD4<Float>
    ) -> [ViewportBody] {
        let gridPolylines = surface.drawGrid(uLineCount: 10, vLineCount: 10, pointsPerLine: 50)
        var edges: [[SIMD3<Float>]] = []
        for polyline in gridPolylines {
            let floatPolyline: [SIMD3<Float>] = polyline.map {
                SIMD3<Float>(
                    Float($0.x + offset.x),
                    Float($0.y + offset.y),
                    Float($0.z + offset.z)
                )
            }
            if floatPolyline.count >= 2 {
                edges.append(floatPolyline)
            }
        }
        return [ViewportBody(
            id: idPrefix, vertexData: [], indices: [], edges: edges, color: color
        )]
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
