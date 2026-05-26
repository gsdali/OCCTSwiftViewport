// SurfaceGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift Surface features as wireframe grids and meshes in 3D space.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in surface gallery that renders OCCTSwift Surface instances
/// as wireframe grids arranged in 3D space.
enum SurfaceGallery {

    // MARK: - Analytic Surfaces

    /// Plane, cylinder, cone, sphere, and torus — each trimmed and arranged in a row.
    static func analyticSurfaces() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        let spacing = 6.0

        // Plane patch (gray)
        if let plane = Surface.plane(origin: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1)) {
            if let trimmed = plane.trimmed(u1: -2, u2: 2, v1: -2, v2: 2) {
                bodies.append(contentsOf: surfaceToGridBodies(
                    trimmed, idPrefix: "surf-plane", offset: SIMD3(-2 * spacing, 0, 0),
                    uColor: SIMD4(0.6, 0.6, 0.6, 1.0),
                    vColor: SIMD4(0.4, 0.4, 0.4, 1.0)
                ))
            }
        }

        // Cylinder (blue)
        if let cyl = Surface.cylinder(
            origin: SIMD3(0, 0, 0), axis: SIMD3(0, 0, 1), radius: 1.5
        ) {
            if let trimmed = cyl.trimmed(u1: 0, u2: .pi * 1.5, v1: 0, v2: 3) {
                bodies.append(contentsOf: surfaceToGridBodies(
                    trimmed, idPrefix: "surf-cyl", offset: SIMD3(-spacing, 0, 0),
                    uColor: SIMD4(0.2, 0.4, 1.0, 1.0),
                    vColor: SIMD4(0.1, 0.3, 0.7, 1.0)
                ))
            }
        }

        // Cone (green)
        if let cone = Surface.cone(
            origin: SIMD3(0, 0, 0), axis: SIMD3(0, 0, 1),
            radius: 1.5, semiAngle: .pi / 6
        ) {
            if let trimmed = cone.trimmed(u1: 0, u2: .pi * 1.5, v1: 0, v2: 3) {
                bodies.append(contentsOf: surfaceToGridBodies(
                    trimmed, idPrefix: "surf-cone", offset: SIMD3(0, 0, 0),
                    uColor: SIMD4(0.2, 0.8, 0.3, 1.0),
                    vColor: SIMD4(0.1, 0.6, 0.2, 1.0)
                ))
            }
        }

        // Sphere (red)
        if let sphere = Surface.sphere(center: SIMD3(0, 0, 0), radius: 2.0) {
            if let trimmed = sphere.trimmed(
                u1: -.pi * 0.8, u2: .pi * 0.8,
                v1: -.pi / 3, v2: .pi / 3
            ) {
                bodies.append(contentsOf: surfaceToGridBodies(
                    trimmed, idPrefix: "surf-sphere", offset: SIMD3(spacing, 0, 0),
                    uColor: SIMD4(1.0, 0.3, 0.2, 1.0),
                    vColor: SIMD4(0.7, 0.2, 0.1, 1.0)
                ))
            }
        }

        // Torus (orange)
        if let torus = Surface.torus(
            origin: SIMD3(0, 0, 0), axis: SIMD3(0, 0, 1),
            majorRadius: 2.0, minorRadius: 0.6
        ) {
            if let trimmed = torus.trimmed(
                u1: 0, u2: .pi * 1.5,
                v1: 0, v2: .pi * 1.5
            ) {
                bodies.append(contentsOf: surfaceToGridBodies(
                    trimmed, idPrefix: "surf-torus", offset: SIMD3(2 * spacing, 0, 0),
                    uColor: SIMD4(1.0, 0.6, 0.1, 1.0),
                    vColor: SIMD4(0.8, 0.4, 0.1, 1.0)
                ))
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Analytic surfaces: plane, cylinder, cone, sphere, torus"
        )
    }

    // MARK: - Swept Surfaces

    /// Extrusion and revolution surfaces.
    static func sweptSurfaces() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Extrusion: profile curve extruded along a direction
        if let profile = Curve3D.interpolate(points: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 1), SIMD3(2, 0, 0.5), SIMD3(3, 0, 0)
        ]) {
            if let extrusion = Surface.extrusion(
                profile: profile, direction: SIMD3(0, 1, 0)
            ) {
                if let trimmed = extrusion.trimmed(
                    u1: extrusion.domain.uMin,
                    u2: extrusion.domain.uMax,
                    v1: 0, v2: 4
                ) {
                    bodies.append(contentsOf: surfaceToGridBodies(
                        trimmed, idPrefix: "surf-extrude", offset: SIMD3(-4, 0, 0),
                        uColor: SIMD4(0.2, 0.7, 1.0, 1.0),
                        vColor: SIMD4(0.1, 0.5, 0.8, 1.0)
                    ))
                }
            }
        }

        // Revolution: meridian curve revolved around Z axis
        if let meridian = Curve3D.interpolate(points: [
            SIMD3(1, 0, 0), SIMD3(1.5, 0, 1), SIMD3(0.8, 0, 2), SIMD3(1.2, 0, 3)
        ]) {
            if let revolution = Surface.revolution(
                meridian: meridian,
                axisOrigin: SIMD3(0, 0, 0),
                axisDirection: SIMD3(0, 0, 1)
            ) {
                if let trimmed = revolution.trimmed(
                    u1: 0, u2: .pi * 1.5,
                    v1: revolution.domain.vMin,
                    v2: revolution.domain.vMax
                ) {
                    bodies.append(contentsOf: surfaceToGridBodies(
                        trimmed, idPrefix: "surf-revolve", offset: SIMD3(4, 0, 0),
                        uColor: SIMD4(0.9, 0.4, 0.2, 1.0),
                        vColor: SIMD4(0.7, 0.3, 0.1, 1.0)
                    ))
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Swept surfaces: extrusion (blue) and revolution (orange)"
        )
    }

    // MARK: - Freeform Surfaces

    /// Bezier patch and BSpline surface.
    static func freeformSurfaces() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // 4x4 Bezier patch
        let bezierPoles: [[SIMD3<Double>]] = [
            [SIMD3(-3, -3, 0), SIMD3(-1, -3, 1), SIMD3(1, -3, -1), SIMD3(3, -3, 0)],
            [SIMD3(-3, -1, 1), SIMD3(-1, -1, 3), SIMD3(1, -1, 0),  SIMD3(3, -1, 1)],
            [SIMD3(-3,  1, 0), SIMD3(-1,  1, 0), SIMD3(1,  1, 2),  SIMD3(3,  1, 0)],
            [SIMD3(-3,  3, 0), SIMD3(-1,  3, -1), SIMD3(1,  3, 1), SIMD3(3,  3, 0)],
        ]

        if let bezier = Surface.bezier(poles: bezierPoles) {
            bodies.append(contentsOf: surfaceToGridBodies(
                bezier, idPrefix: "surf-bezier", offset: SIMD3(-5, 0, 0),
                uColor: SIMD4(0.2, 0.9, 0.4, 1.0),
                vColor: SIMD4(0.1, 0.7, 0.3, 1.0)
            ))

            // Show control net
            var netEdges: [[SIMD3<Float>]] = []
            // U-direction control rows
            for row in bezierPoles {
                let polyline: [SIMD3<Float>] = row.map {
                    SIMD3<Float>(Float($0.x) - 5, Float($0.y), Float($0.z))
                }
                netEdges.append(polyline)
            }
            // V-direction control columns
            for col in 0..<bezierPoles[0].count {
                let polyline: [SIMD3<Float>] = bezierPoles.map {
                    SIMD3<Float>(Float($0[col].x) - 5, Float($0[col].y), Float($0[col].z))
                }
                netEdges.append(polyline)
            }
            bodies.append(ViewportBody(
                id: "surf-bezier-net",
                vertexData: [],
                indices: [],
                edges: netEdges,
                color: SIMD4(0.5, 0.5, 0.5, 0.4)
            ))
        }

        // BSpline surface through scattered points
        let bsPoles: [[SIMD3<Double>]] = [
            [SIMD3(-2, -2, 0), SIMD3(0, -2, 1.5), SIMD3(2, -2, 0)],
            [SIMD3(-2,  0, 1), SIMD3(0,  0, 2.5), SIMD3(2,  0, 0.5)],
            [SIMD3(-2,  2, 0), SIMD3(0,  2, 1),   SIMD3(2,  2, 0)],
        ]

        if let bspline = Surface.bezier(poles: bsPoles) {
            bodies.append(contentsOf: surfaceToGridBodies(
                bspline, idPrefix: "surf-bspline", offset: SIMD3(5, 0, 0),
                uColor: SIMD4(1.0, 0.5, 0.2, 1.0),
                vColor: SIMD4(0.8, 0.3, 0.1, 1.0)
            ))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Freeform surfaces: Bezier patch with control net (green), BSpline (orange)"
        )
    }

    // MARK: - Pipe Surfaces

    /// Circular and custom-section pipes along curved spines.
    static func pipeSurfaces() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Circular pipe along a BSpline spine
        if let spine = Curve3D.interpolate(points: [
            SIMD3(0, 0, 0), SIMD3(2, 1, 1), SIMD3(4, 0, 2), SIMD3(6, -1, 1), SIMD3(8, 0, 0)
        ]) {
            if let pipe = Surface.pipe(path: spine, radius: 0.3) {
                bodies.append(contentsOf: surfaceToGridBodies(
                    pipe, idPrefix: "surf-pipe-circ", offset: SIMD3(-4, 0, 0),
                    uColor: SIMD4(0.3, 0.6, 1.0, 1.0),
                    vColor: SIMD4(0.2, 0.4, 0.8, 1.0),
                    uLines: 20, vLines: 12
                ))
            }

            // Custom section pipe — elliptical cross section
            if let section = Curve3D.ellipse(
                center: spine.point(at: spine.domain.lowerBound),
                normal: SIMD3(1, 0, 0),
                majorRadius: 0.5,
                minorRadius: 0.2
            ) {
                if let customPipe = Surface.pipe(path: spine, section: section) {
                    bodies.append(contentsOf: surfaceToGridBodies(
                        customPipe, idPrefix: "surf-pipe-custom", offset: SIMD3(-4, 4, 0),
                        uColor: SIMD4(0.9, 0.4, 0.2, 1.0),
                        vColor: SIMD4(0.7, 0.3, 0.1, 1.0),
                        uLines: 20, vLines: 12
                    ))
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Pipe surfaces: circular pipe (blue), elliptical pipe (orange)"
        )
    }

    // MARK: - Iso Curves

    /// A BSpline surface with highlighted U and V iso-parameter curves.
    static func isoCurves() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a curved surface
        let poles: [[SIMD3<Double>]] = [
            [SIMD3(-3, -3, 0), SIMD3(-1, -3, 2), SIMD3(1, -3, -1), SIMD3(3, -3, 0)],
            [SIMD3(-3, -1, 1), SIMD3(-1, -1, 3), SIMD3(1, -1, 1),  SIMD3(3, -1, 0)],
            [SIMD3(-3,  1, 0), SIMD3(-1,  1, 1), SIMD3(1,  1, 2),  SIMD3(3,  1, 1)],
            [SIMD3(-3,  3, 0), SIMD3(-1,  3, 0), SIMD3(1,  3, 1),  SIMD3(3,  3, 0)],
        ]

        guard let surface = Surface.bezier(poles: poles) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create surface")
        }

        // Render the surface grid (dim gray)
        bodies.append(contentsOf: surfaceToGridBodies(
            surface, idPrefix: "surf-iso-base", offset: .zero,
            uColor: SIMD4(0.3, 0.3, 0.3, 0.4),
            vColor: SIMD4(0.3, 0.3, 0.3, 0.4)
        ))

        let domain = surface.domain

        // Extract U iso-curves (red)
        let uCount = 5
        for i in 0...uCount {
            let u = domain.uMin + Double(i) / Double(uCount) * (domain.uMax - domain.uMin)
            if let isoCurve = surface.uIso(at: u) {
                let pts = isoCurve.drawAdaptive()
                let polyline: [SIMD3<Float>] = pts.map {
                    SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
                }
                bodies.append(ViewportBody(
                    id: "surf-iso-u-\(i)",
                    vertexData: [],
                    indices: [],
                    edges: [polyline],
                    color: SIMD4(1.0, 0.2, 0.2, 1.0)
                ))
            }
        }

        // Extract V iso-curves (cyan)
        let vCount = 5
        for i in 0...vCount {
            let v = domain.vMin + Double(i) / Double(vCount) * (domain.vMax - domain.vMin)
            if let isoCurve = surface.vIso(at: v) {
                let pts = isoCurve.drawAdaptive()
                let polyline: [SIMD3<Float>] = pts.map {
                    SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
                }
                bodies.append(ViewportBody(
                    id: "surf-iso-v-\(i)",
                    vertexData: [],
                    indices: [],
                    edges: [polyline],
                    color: SIMD4(0.0, 0.8, 0.9, 1.0)
                ))
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Iso curves: U-isos (red), V-isos (cyan) on Bezier surface"
        )
    }

    // MARK: - Helpers

    /// Converts a surface to a pair of wireframe grid bodies (U-lines and V-lines).
    private static func surfaceToGridBodies(
        _ surface: Surface,
        idPrefix: String,
        offset: SIMD3<Double>,
        uColor: SIMD4<Float>,
        vColor: SIMD4<Float>,
        uLines: Int = 10,
        vLines: Int = 10
    ) -> [ViewportBody] {
        let gridPolylines = surface.drawGrid(
            uLineCount: uLines, vLineCount: vLines, pointsPerLine: 50
        )

        // Split into U-lines and V-lines
        let totalLines = uLines + vLines
        var uEdges: [[SIMD3<Float>]] = []
        var vEdges: [[SIMD3<Float>]] = []

        for (i, polyline) in gridPolylines.enumerated() {
            let floatPolyline: [SIMD3<Float>] = polyline.map {
                SIMD3<Float>(
                    Float($0.x + offset.x),
                    Float($0.y + offset.y),
                    Float($0.z + offset.z)
                )
            }
            guard floatPolyline.count >= 2 else { continue }

            if i < uLines {
                uEdges.append(floatPolyline)
            } else if i < totalLines {
                vEdges.append(floatPolyline)
            } else {
                // Extra lines go to U
                uEdges.append(floatPolyline)
            }
        }

        var bodies: [ViewportBody] = []

        if !uEdges.isEmpty {
            bodies.append(ViewportBody(
                id: "\(idPrefix)-u",
                vertexData: [],
                indices: [],
                edges: uEdges,
                color: uColor
            ))
        }

        if !vEdges.isEmpty {
            bodies.append(ViewportBody(
                id: "\(idPrefix)-v",
                vertexData: [],
                indices: [],
                edges: vEdges,
                color: vColor
            ))
        }

        return bodies
    }
}
