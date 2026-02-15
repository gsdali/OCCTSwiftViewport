// AnnotationGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift AIS annotations — dimensions, text labels, and point clouds.
// Shows how to create measurement annotations and render their geometry for Metal display.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in gallery demonstrating AIS annotation features.
/// Each demo creates dimension measurements, text labels, or point clouds
/// and visualizes their geometry as viewport bodies.
enum AnnotationGallery {

    // MARK: - Length & Distance Dimensions

    /// Creates length dimensions between points, on edges, and between faces.
    static func lengthDimensions() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Length dimensions"

        // Create a box to measure
        guard let box = Shape.box(width: 4, height: 3, depth: 2) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create box")
        }

        // Show the box
        let (boxBody, _) = CADFileLoader.shapeToBodyAndMetadata(
            box, id: "annot-len-box",
            color: SIMD4(0.3, 0.6, 1.0, 0.5)
        )
        if let b = boxBody { bodies.append(b) }

        // Point-to-point dimension
        let p1 = SIMD3<Double>(0, 0, 0)
        let p2 = SIMD3<Double>(4, 0, 0)
        if let dim = LengthDimension(from: p1, to: p2) {
            info += "\nPoint-to-point: \(String(format: "%.2f", dim.value))"
            if let geom = dim.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-len-p2p",
                    color: SIMD4(1.0, 0.4, 0.2, 1.0)
                ))
            }
        }

        // Vertical dimension
        let p3 = SIMD3<Double>(0, 0, 0)
        let p4 = SIMD3<Double>(0, 3, 0)
        if let dim2 = LengthDimension(from: p3, to: p4) {
            info += "\nVertical: \(String(format: "%.2f", dim2.value))"
            if let geom = dim2.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-len-vert",
                    color: SIMD4(0.2, 1.0, 0.4, 1.0),
                    offsetX: -1.5
                ))
            }
        }

        // Diagonal dimension
        let p5 = SIMD3<Double>(0, 0, 0)
        let p6 = SIMD3<Double>(4, 3, 2)
        if let dim3 = LengthDimension(from: p5, to: p6) {
            info += "\nDiagonal: \(String(format: "%.2f", dim3.value))"
            if let geom = dim3.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-len-diag",
                    color: SIMD4(1.0, 1.0, 0.2, 1.0),
                    offsetY: 1.5
                ))
            }
        }

        info += "\nFace count: \(box.faces().count)"
        info += "\nEdge count: \(box.edges().count)"

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Radius & Diameter Dimensions

    /// Creates radius and diameter dimensions on cylindrical/spherical shapes.
    static func radialDimensions() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Radius & diameter dimensions"

        // Create a cylinder
        guard let cyl = Shape.cylinder(radius: 1.5, height: 3) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create cylinder")
        }

        // Show the cylinder
        let (cylBody, _) = CADFileLoader.shapeToBodyAndMetadata(
            cyl, id: "annot-rad-cyl",
            color: SIMD4(0.4, 0.7, 0.9, 0.5)
        )
        if var b = cylBody {
            b = offsetBody(b, dx: -4, id: "annot-rad-cyl")
            bodies.append(b)
        }

        // Radius dimension on cylinder
        if let radDim = RadiusDimension(shape: cyl) {
            info += "\nCylinder radius: \(String(format: "%.2f", radDim.value))"
            if let geom = radDim.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-rad-cyl-dim",
                    color: SIMD4(1.0, 0.5, 0.2, 1.0),
                    offsetX: -4
                ))
            }
        }

        // Diameter dimension on cylinder
        if let diaDim = DiameterDimension(shape: cyl) {
            info += "\nCylinder diameter: \(String(format: "%.2f", diaDim.value))"
            if let geom = diaDim.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-dia-cyl-dim",
                    color: SIMD4(0.2, 1.0, 0.5, 1.0),
                    offsetX: -4, offsetY: -2
                ))
            }
        }

        // Create a sphere
        guard let sph = Shape.sphere(radius: 1.2) else {
            return Curve2DGallery.GalleryResult(bodies: bodies, description: info + "\nFailed to create sphere")
        }

        let (sphBody, _) = CADFileLoader.shapeToBodyAndMetadata(
            sph, id: "annot-rad-sph",
            color: SIMD4(0.9, 0.5, 0.7, 0.5)
        )
        if var b = sphBody {
            b = offsetBody(b, dx: 4, id: "annot-rad-sph")
            bodies.append(b)
        }

        // Radius on sphere
        if let sphRad = RadiusDimension(shape: sph) {
            info += "\nSphere radius: \(String(format: "%.2f", sphRad.value))"
            if let geom = sphRad.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-rad-sph-dim",
                    color: SIMD4(1.0, 0.3, 0.8, 1.0),
                    offsetX: 4
                ))
            }
        }

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Angle Dimensions

    /// Creates angle dimensions between edges and from three points.
    static func angleDimensions() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Angle dimensions"

        // Three-point angle
        let a = SIMD3<Double>(3, 0, 0)
        let vertex = SIMD3<Double>(0, 0, 0)
        let b = SIMD3<Double>(0, 3, 0)

        if let angleDim = AngleDimension(first: a, vertex: vertex, second: b) {
            info += "\n3-point angle: \(String(format: "%.1f", angleDim.degrees)) deg"
            if let geom = angleDim.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-ang-3pt",
                    color: SIMD4(1.0, 0.6, 0.2, 1.0)
                ))
            }
        }

        // Show the angle arms as edge lines
        bodies.append(ViewportBody(
            id: "annot-ang-arm1",
            vertexData: [], indices: [],
            edges: [[
                SIMD3<Float>(Float(vertex.x), Float(vertex.y), Float(vertex.z)),
                SIMD3<Float>(Float(a.x), Float(a.y), Float(a.z))
            ]],
            color: SIMD4(0.7, 0.7, 0.7, 0.8)
        ))
        bodies.append(ViewportBody(
            id: "annot-ang-arm2",
            vertexData: [], indices: [],
            edges: [[
                SIMD3<Float>(Float(vertex.x), Float(vertex.y), Float(vertex.z)),
                SIMD3<Float>(Float(b.x), Float(b.y), Float(b.z))
            ]],
            color: SIMD4(0.7, 0.7, 0.7, 0.8)
        ))

        // Second angle: 60 degrees
        let c = SIMD3<Double>(3, 0, 0)
        let v2 = SIMD3<Double>(0, 0, 0)
        let d = SIMD3<Double>(1.5, 2.598, 0) // cos(60)*3, sin(60)*3

        if let ang2 = AngleDimension(first: c, vertex: v2, second: d) {
            info += "\n60-deg angle: \(String(format: "%.1f", ang2.degrees)) deg"
            if let geom = ang2.geometry, geom.isValid {
                bodies.append(contentsOf: dimensionGeometryBodies(
                    geom, prefix: "annot-ang-60",
                    color: SIMD4(0.2, 0.8, 1.0, 1.0),
                    offsetX: 6
                ))
            }
        }

        bodies.append(ViewportBody(
            id: "annot-ang-arm3",
            vertexData: [], indices: [],
            edges: [[SIMD3<Float>(6, 0, 0), SIMD3<Float>(9, 0, 0)]],
            color: SIMD4(0.7, 0.7, 0.7, 0.8)
        ))
        bodies.append(ViewportBody(
            id: "annot-ang-arm4",
            vertexData: [], indices: [],
            edges: [[SIMD3<Float>(6, 0, 0), SIMD3<Float>(7.5, Float(2.598), 0)]],
            color: SIMD4(0.7, 0.7, 0.7, 0.8)
        ))

        // Marker spheres at vertices
        bodies.append(markerSphere(at: SIMD3(0, 0, 0), radius: 0.1, color: SIMD4(1, 1, 1, 1), id: "annot-ang-v1"))
        bodies.append(markerSphere(at: SIMD3(6, 0, 0), radius: 0.1, color: SIMD4(1, 1, 1, 1), id: "annot-ang-v2"))

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Text Labels & Point Cloud

    /// Creates text labels at 3D positions and a colored point cloud.
    static func labelsAndPointCloud() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Text labels & point cloud"

        // Create text labels
        let labelPositions: [(String, SIMD3<Double>)] = [
            ("Origin", SIMD3(0, 0, 0)),
            ("X-Axis", SIMD3(5, 0, 0)),
            ("Y-Axis", SIMD3(0, 5, 0)),
            ("Z-Axis", SIMD3(0, 0, 5)),
        ]

        for (i, (text, pos)) in labelPositions.enumerated() {
            if let label = TextLabel(text: text, position: pos) {
                label.setHeight(0.5)
                info += "\nLabel '\(label.text)' at (\(String(format: "%.0f,%.0f,%.0f", pos.x, pos.y, pos.z)))"

                // Render label position as a small sphere
                let fPos = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
                bodies.append(markerSphere(
                    at: fPos, radius: 0.15,
                    color: SIMD4(1.0, 0.8, 0.2, 1.0),
                    id: "annot-label-\(i)"
                ))

                // Draw a line from origin to label position
                if pos != SIMD3(0, 0, 0) {
                    bodies.append(ViewportBody(
                        id: "annot-label-line-\(i)",
                        vertexData: [], indices: [],
                        edges: [[SIMD3<Float>(0, 0, 0), fPos]],
                        color: SIMD4(0.5, 0.5, 0.5, 0.4)
                    ))
                }
            }
        }

        // Create a colored point cloud
        var cloudPoints: [SIMD3<Double>] = []
        var cloudColors: [SIMD3<Float>] = []

        // Generate a spherical point cloud
        let n = 50
        for i in 0..<n {
            let phi = Double(i) / Double(n) * 2 * .pi
            let theta = Double(i) * 0.618033988749895 * 2 * .pi // golden angle
            let r = 2.0 + 0.5 * sin(3 * phi)
            let x = r * sin(phi) * cos(theta) + 8.0 // offset to the right
            let y = r * sin(phi) * sin(theta)
            let z = r * cos(phi)
            cloudPoints.append(SIMD3(x, y, z))

            // Color by height: blue (low) to red (high)
            let t = Float((z + 3) / 6.0)
            cloudColors.append(SIMD3(t, 0.3, 1.0 - t))
        }

        if let cloud = PointCloud(points: cloudPoints, colors: cloudColors) {
            info += "\nPoint cloud: \(cloud.count) points"
            if let bounds = cloud.bounds {
                info += "\nBounds: (\(String(format: "%.1f", bounds.min.x))...\(String(format: "%.1f", bounds.max.x)))"
            }

            // Render each point as a small sphere
            let pts = cloud.points
            let cols = cloud.colors
            for (i, pt) in pts.enumerated() {
                let fPt = SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z))
                let col = i < cols.count ? cols[i] : SIMD3<Float>(0.8, 0.8, 0.8)
                bodies.append(markerSphere(
                    at: fPt, radius: 0.08,
                    color: SIMD4(col.x, col.y, col.z, 1.0),
                    id: "annot-cloud-\(i)"
                ))
            }
        }

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Helpers

    /// Converts a DimensionGeometry into viewport edge-line bodies (extension lines + dimension line).
    private static func dimensionGeometryBodies(
        _ geom: DimensionGeometry,
        prefix: String,
        color: SIMD4<Float>,
        offsetX: Float = 0,
        offsetY: Float = 0
    ) -> [ViewportBody] {
        var bodies: [ViewportBody] = []

        let p1 = SIMD3<Float>(Float(geom.firstPoint.x) + offsetX,
                               Float(geom.firstPoint.y) + offsetY,
                               Float(geom.firstPoint.z))
        let p2 = SIMD3<Float>(Float(geom.secondPoint.x) + offsetX,
                               Float(geom.secondPoint.y) + offsetY,
                               Float(geom.secondPoint.z))
        let txt = SIMD3<Float>(Float(geom.textPosition.x) + offsetX,
                                Float(geom.textPosition.y) + offsetY,
                                Float(geom.textPosition.z))

        // Main dimension line
        bodies.append(ViewportBody(
            id: "\(prefix)-dimline",
            vertexData: [], indices: [],
            edges: [[p1, p2]],
            color: color
        ))

        // Extension lines to text position
        bodies.append(ViewportBody(
            id: "\(prefix)-ext1",
            vertexData: [], indices: [],
            edges: [[p1, txt]],
            color: SIMD4(color.x, color.y, color.z, color.w * 0.5)
        ))

        // Marker spheres at attachment points
        bodies.append(markerSphere(at: p1, radius: 0.06, color: color, id: "\(prefix)-m1"))
        bodies.append(markerSphere(at: p2, radius: 0.06, color: color, id: "\(prefix)-m2"))

        // Text position marker
        let dimColor = SIMD4<Float>(1.0, 1.0, 1.0, 0.8)
        bodies.append(markerSphere(at: txt, radius: 0.05, color: dimColor, id: "\(prefix)-txt"))

        return bodies
    }

    /// Creates a small sphere ViewportBody at the given position.
    private static func markerSphere(
        at position: SIMD3<Float>, radius: Float,
        color: SIMD4<Float>, id: String
    ) -> ViewportBody {
        var sphere = ViewportBody.sphere(
            id: id, radius: radius, segments: 8, rings: 6, color: color
        )
        // Offset sphere vertices to position
        let stride = 6
        var newVerts: [Float] = []
        newVerts.reserveCapacity(sphere.vertexData.count)
        for i in Swift.stride(from: 0, to: sphere.vertexData.count, by: stride) {
            newVerts.append(sphere.vertexData[i] + position.x)
            newVerts.append(sphere.vertexData[i + 1] + position.y)
            newVerts.append(sphere.vertexData[i + 2] + position.z)
            newVerts.append(sphere.vertexData[i + 3])
            newVerts.append(sphere.vertexData[i + 4])
            newVerts.append(sphere.vertexData[i + 5])
        }
        sphere.vertexData = newVerts
        return sphere
    }

    /// Offsets a ViewportBody by dx along X.
    private static func offsetBody(
        _ body: ViewportBody, dx: Float, id: String
    ) -> ViewportBody {
        let stride = 6
        var newVerts: [Float] = []
        newVerts.reserveCapacity(body.vertexData.count)
        for i in Swift.stride(from: 0, to: body.vertexData.count, by: stride) {
            newVerts.append(body.vertexData[i] + dx)
            newVerts.append(body.vertexData[i + 1])
            newVerts.append(body.vertexData[i + 2])
            newVerts.append(body.vertexData[i + 3])
            newVerts.append(body.vertexData[i + 4])
            newVerts.append(body.vertexData[i + 5])
        }
        let newEdges = body.edges.map { polyline in
            polyline.map { SIMD3($0.x + dx, $0.y, $0.z) }
        }
        return ViewportBody(
            id: id,
            vertexData: newVerts,
            indices: body.indices,
            edges: newEdges,
            faceIndices: body.faceIndices,
            color: body.color
        )
    }
}
