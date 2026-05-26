// PlateGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift plate surface creation and NLPlate deformation.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in plate surface gallery showing surface fitting and deformation.
enum PlateGallery {

    // MARK: - Plate from Points

    /// Creates a smooth BSpline plate surface through scattered 3D points.
    static func plateFromPoints() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Generate a terrain-like grid of 3D points
        var points: [SIMD3<Double>] = []
        let gridSize = 5
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                let x = Double(i) - Double(gridSize - 1) / 2.0
                let y = Double(j) - Double(gridSize - 1) / 2.0
                // Sine-wave terrain with some variation
                let z = sin(x * 0.8) * cos(y * 0.8) * 1.5 + Double.random(in: -0.1...0.1)
                points.append(SIMD3(x, y, z))
            }
        }

        // Show the source points as spheres (yellow)
        for (i, pt) in points.enumerated() {
            let pos = SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z))
            bodies.append(makeMarkerSphere(at: pos, radius: 0.1,
                                           id: "plate-pt-\(i)",
                                           color: SIMD4(1.0, 0.9, 0.2, 1.0)))
        }

        // Create a plate surface through the points
        if let plateSurface = Surface.plateThrough(points, degree: 3, tolerance: 0.01) {
            bodies.append(contentsOf: surfaceGridBodies(
                plateSurface, idPrefix: "plate-surface", offset: .zero,
                uColor: SIMD4(0.2, 0.6, 1.0, 1.0),
                vColor: SIMD4(0.1, 0.4, 0.8, 1.0)
            ))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Plate from points: smooth surface through scattered 3D points"
        )
    }

    // MARK: - Deformed Plate (G0)

    /// Creates a flat plate and deforms it with G0 position constraints.
    static func deformedPlate() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a flat plane surface
        guard let plane = Surface.plane(origin: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1)),
              let flatSurface = plane.trimmed(u1: -3, u2: 3, v1: -3, v2: 3) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create plane")
        }

        // Show the original flat surface (transparent gray)
        bodies.append(contentsOf: surfaceGridBodies(
            flatSurface, idPrefix: "plate-orig", offset: .zero,
            uColor: SIMD4(0.5, 0.5, 0.5, 0.3),
            vColor: SIMD4(0.4, 0.4, 0.4, 0.3)
        ))

        // Define displacement constraints: push some UV points to new 3D targets
        let constraints: [(uv: SIMD2<Double>, target: SIMD3<Double>)] = [
            (uv: SIMD2(0.5, 0.5), target: SIMD3(0, 0, 2.0)),    // center up
            (uv: SIMD2(0.2, 0.2), target: SIMD3(-1.8, -1.8, 0.5)),
            (uv: SIMD2(0.8, 0.2), target: SIMD3(1.8, -1.8, -0.5)),
            (uv: SIMD2(0.2, 0.8), target: SIMD3(-1.8, 1.8, 0.3)),
            (uv: SIMD2(0.8, 0.8), target: SIMD3(1.8, 1.8, 1.0)),
        ]

        // Apply NLPlate G0 deformation
        if let deformed = flatSurface.nlPlateDeformed(constraints: constraints) {
            bodies.append(contentsOf: surfaceGridBodies(
                deformed, idPrefix: "plate-deformed", offset: .zero,
                uColor: SIMD4(0.2, 0.8, 0.4, 1.0),
                vColor: SIMD4(0.1, 0.6, 0.3, 1.0)
            ))
        }

        // Show constraint target points (red spheres)
        for (i, c) in constraints.enumerated() {
            let pos = SIMD3<Float>(Float(c.target.x), Float(c.target.y), Float(c.target.z))
            bodies.append(makeMarkerSphere(at: pos, radius: 0.12,
                                           id: "plate-constraint-\(i)",
                                           color: SIMD4(1.0, 0.3, 0.3, 1.0)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Deformed plate: original (gray), G0-deformed (green), targets (red)"
        )
    }

    // MARK: - Tangent Deformation (G1)

    /// Creates a plate with G1 tangent-controlled deformation.
    static func tangentDeformation() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a flat plane surface
        guard let plane = Surface.plane(origin: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1)),
              let flatSurface = plane.trimmed(u1: -3, u2: 3, v1: -3, v2: 3) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create plane")
        }

        // Show original flat surface (transparent)
        bodies.append(contentsOf: surfaceGridBodies(
            flatSurface, idPrefix: "tplate-orig", offset: .zero,
            uColor: SIMD4(0.5, 0.5, 0.5, 0.3),
            vColor: SIMD4(0.4, 0.4, 0.4, 0.3)
        ))

        // G1 constraints: position + tangent directions
        let g1Constraints: [(uv: SIMD2<Double>, target: SIMD3<Double>,
                             tangentU: SIMD3<Double>, tangentV: SIMD3<Double>)] = [
            (uv: SIMD2(0.5, 0.5),
             target: SIMD3(0, 0, 2.0),
             tangentU: SIMD3(1, 0, 0.5),   // tilted U tangent
             tangentV: SIMD3(0, 1, -0.3)),  // tilted V tangent
            (uv: SIMD2(0.25, 0.5),
             target: SIMD3(-1.5, 0, 1.0),
             tangentU: SIMD3(1, 0, 0),
             tangentV: SIMD3(0, 1, 0)),
            (uv: SIMD2(0.75, 0.5),
             target: SIMD3(1.5, 0, 0.5),
             tangentU: SIMD3(1, 0, -0.2),
             tangentV: SIMD3(0, 1, 0)),
        ]

        // Apply NLPlate G1 deformation
        if let deformed = flatSurface.nlPlateDeformedG1(constraints: g1Constraints) {
            bodies.append(contentsOf: surfaceGridBodies(
                deformed, idPrefix: "tplate-deformed", offset: .zero,
                uColor: SIMD4(0.8, 0.3, 0.9, 1.0),
                vColor: SIMD4(0.6, 0.2, 0.7, 1.0)
            ))
        }

        // Show constraint points with tangent direction arrows
        let arrowLength: Float = 0.8
        for (i, c) in g1Constraints.enumerated() {
            let pos = SIMD3<Float>(Float(c.target.x), Float(c.target.y), Float(c.target.z))
            bodies.append(makeMarkerSphere(at: pos, radius: 0.1,
                                           id: "tplate-pt-\(i)",
                                           color: SIMD4(1.0, 0.3, 0.3, 1.0)))

            // Tangent U direction (green arrow)
            let tu = SIMD3<Float>(Float(c.tangentU.x), Float(c.tangentU.y), Float(c.tangentU.z))
            let tuNorm = simd_normalize(tu) * arrowLength
            bodies.append(ViewportBody(
                id: "tplate-tu-\(i)",
                vertexData: [],
                indices: [],
                edges: [[pos, pos + tuNorm]],
                color: SIMD4(0.2, 0.9, 0.2, 1.0)
            ))

            // Tangent V direction (blue arrow)
            let tv = SIMD3<Float>(Float(c.tangentV.x), Float(c.tangentV.y), Float(c.tangentV.z))
            let tvNorm = simd_normalize(tv) * arrowLength
            bodies.append(ViewportBody(
                id: "tplate-tv-\(i)",
                vertexData: [],
                indices: [],
                edges: [[pos, pos + tvNorm]],
                color: SIMD4(0.2, 0.2, 0.9, 1.0)
            ))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Tangent deformation: original (gray), G1-deformed (purple), tangent arrows"
        )
    }

    // MARK: - Helpers

    private static func surfaceGridBodies(
        _ surface: Surface,
        idPrefix: String,
        offset: SIMD3<Double>,
        uColor: SIMD4<Float>,
        vColor: SIMD4<Float>
    ) -> [ViewportBody] {
        let gridPolylines = surface.drawGrid(
            uLineCount: 12, vLineCount: 12, pointsPerLine: 50
        )

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
            if i < 12 {
                uEdges.append(floatPolyline)
            } else {
                vEdges.append(floatPolyline)
            }
        }

        var bodies: [ViewportBody] = []
        if !uEdges.isEmpty {
            bodies.append(ViewportBody(
                id: "\(idPrefix)-u", vertexData: [], indices: [],
                edges: uEdges, color: uColor
            ))
        }
        if !vEdges.isEmpty {
            bodies.append(ViewportBody(
                id: "\(idPrefix)-v", vertexData: [], indices: [],
                edges: vEdges, color: vColor
            ))
        }
        return bodies
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
