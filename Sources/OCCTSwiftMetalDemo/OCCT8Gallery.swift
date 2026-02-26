// OCCT8Gallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates new OCCT 8.0.0-rc4 features from OCCTSwift v0.28 and v0.29.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Gallery showcasing OCCT 8.0.0-rc4 features: helix curves, KD-tree queries,
/// wedge primitives, hatch patterns, polynomial solvers, and shape operations.
enum OCCT8Gallery {

    // MARK: - v0.28: Helix Curves

    /// Constant and tapered helical wires visualized as colored wireframes.
    static func helixCurves() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Constant-radius helix (spring)
        if let spring = Wire.helix(radius: 2.0, pitch: 1.0, turns: 8) {
            bodies.append(wireToBody(spring, id: "helix-spring",
                                     color: SIMD4(0.2, 0.6, 1.0, 1.0)))
        }

        // Tapered helix (cone coil) — offset to the right
        if let taper = Wire.helixTapered(
            origin: SIMD3(8, 0, 0),
            startRadius: 3.0, endRadius: 0.5,
            pitch: 1.5, turns: 6
        ) {
            bodies.append(wireToBody(taper, id: "helix-tapered",
                                     color: SIMD4(1.0, 0.5, 0.1, 1.0)))
        }

        // Clockwise helix — offset left
        if let cw = Wire.helix(
            origin: SIMD3(-8, 0, 0),
            radius: 1.5, pitch: 0.8, turns: 10, clockwise: true
        ) {
            bodies.append(wireToBody(cw, id: "helix-cw",
                                     color: SIMD4(0.3, 0.9, 0.4, 1.0)))
        }

        // Tight thread-like helix
        if let thread = Wire.helix(
            origin: SIMD3(0, 8, 0),
            radius: 1.0, pitch: 0.3, turns: 20
        ) {
            bodies.append(wireToBody(thread, id: "helix-thread",
                                     color: SIMD4(0.9, 0.2, 0.6, 1.0)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Helix curves: constant spring, tapered coil, clockwise, thread"
        )
    }

    // MARK: - v0.28: KD-Tree Spatial Queries

    /// Builds a KD-tree from random points and visualizes nearest/range queries.
    static func kdTreeQueries() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Generate a grid of points with some noise
        var points: [SIMD3<Double>] = []
        for ix in -5...5 {
            for iy in -5...5 {
                for iz in 0...2 {
                    let noise = SIMD3<Double>(
                        Double.random(in: -0.3...0.3),
                        Double.random(in: -0.3...0.3),
                        Double.random(in: -0.3...0.3)
                    )
                    points.append(SIMD3(Double(ix), Double(iy), Double(iz)) + noise)
                }
            }
        }

        // Render all points as small spheres (gray)
        for (i, pt) in points.enumerated() {
            let sphere = makeMarker(
                at: SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z)),
                radius: 0.08, id: "kd-pt-\(i)",
                color: SIMD4(0.5, 0.5, 0.5, 0.6)
            )
            bodies.append(sphere)
        }

        guard let tree = KDTree(points: points) else {
            return Curve2DGallery.GalleryResult(bodies: bodies, description: "KD-tree build failed")
        }

        // Query: nearest to origin
        if let (idx, _) = tree.nearest(to: .zero) {
            let pt = points[idx]
            bodies.append(makeMarker(
                at: SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z)),
                radius: 0.25, id: "kd-nearest",
                color: SIMD4(1.0, 0.2, 0.2, 1.0)
            ))
        }

        // Query: 5 nearest to (3, 3, 1)
        let queryPt = SIMD3<Double>(3, 3, 1)
        let kNearest = tree.kNearest(to: queryPt, k: 5)
        for (i, result) in kNearest.enumerated() {
            let pt = points[result.index]
            bodies.append(makeMarker(
                at: SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z)),
                radius: 0.2, id: "kd-knn-\(i)",
                color: SIMD4(0.2, 1.0, 0.3, 1.0)
            ))
        }
        // Mark query point
        bodies.append(makeMarker(
            at: SIMD3<Float>(Float(queryPt.x), Float(queryPt.y), Float(queryPt.z)),
            radius: 0.15, id: "kd-query-knn",
            color: SIMD4(1.0, 1.0, 0.0, 1.0)
        ))

        // Query: range search — all points within radius 2.0 of (-3, -3, 0)
        let rangePt = SIMD3<Double>(-3, -3, 0)
        let rangeResults = tree.rangeSearch(center: rangePt, radius: 2.0)
        for (i, idx) in rangeResults.enumerated() {
            let pt = points[idx]
            bodies.append(makeMarker(
                at: SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z)),
                radius: 0.18, id: "kd-range-\(i)",
                color: SIMD4(0.3, 0.5, 1.0, 1.0)
            ))
        }
        bodies.append(makeMarker(
            at: SIMD3<Float>(Float(rangePt.x), Float(rangePt.y), Float(rangePt.z)),
            radius: 0.15, id: "kd-query-range",
            color: SIMD4(1.0, 0.5, 0.0, 1.0)
        ))

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "KD-tree: \(points.count) pts, red=nearest, green=5-NN, blue=range(r=2)"
        )
    }

    // MARK: - v0.29: Wedge Primitives

    /// Wedge and advanced wedge shapes — tapered boxes, pyramids.
    static func wedgePrimitives() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Simple wedge (tapered in X)
        if let wedge = Shape.wedge(dx: 3, dy: 2, dz: 2, ltx: 1) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                wedge, id: "wedge-simple", color: SIMD4(0.5, 0.7, 0.9, 1.0)
            )
            if let body { bodies.append(body) }
        }

        // Pyramid (ltx = 0) — offset right
        if let pyramid = Shape.wedge(dx: 2, dy: 3, dz: 2, ltx: 0) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                pyramid, id: "wedge-pyramid", color: SIMD4(0.9, 0.6, 0.3, 1.0)
            )
            if var body {
                offsetBody(&body, dx: 5, dy: 0, dz: 0)
                bodies.append(body)
            }
        }

        // Regular box (ltx = dx) for comparison — offset left
        if let box = Shape.wedge(dx: 2, dy: 2, dz: 2, ltx: 2) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "wedge-box", color: SIMD4(0.6, 0.9, 0.6, 1.0)
            )
            if var body {
                offsetBody(&body, dx: -5, dy: 0, dz: 0)
                bodies.append(body)
            }
        }

        // Advanced wedge with custom top bounds — offset back
        if let adv = Shape.wedge(dx: 4, dy: 2, dz: 4, xmin: 1, zmin: 1, xmax: 3, zmax: 3) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                adv, id: "wedge-advanced", color: SIMD4(0.8, 0.5, 0.8, 1.0)
            )
            if var body {
                offsetBody(&body, dx: 0, dy: 0, dz: 6)
                bodies.append(body)
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Wedge primitives: tapered, pyramid (ltx=0), box (ltx=dx), advanced"
        )
    }

    // MARK: - v0.29: Hatch Patterns

    /// 2D hatch patterns at various angles inside different boundary shapes.
    static func hatchPatterns() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Rectangle boundary with horizontal hatching
        let rect: [SIMD2<Double>] = [
            SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 8), SIMD2(0, 8)
        ]
        let hHatch = HatchPattern.generate(
            boundary: rect,
            direction: SIMD2(1, 0),
            spacing: 0.8
        )
        bodies.append(hatchToBody(hHatch, id: "hatch-horiz",
                                   color: SIMD4(0.3, 0.6, 1.0, 1.0)))
        bodies.append(boundaryToBody(rect, id: "hatch-rect-border",
                                      color: SIMD4(0.9, 0.9, 0.9, 1.0)))

        // Triangle boundary with 45-degree hatching — offset right
        let tri: [SIMD2<Double>] = [
            SIMD2(14, 0), SIMD2(24, 0), SIMD2(19, 8)
        ]
        let diagHatch = HatchPattern.generate(
            boundary: tri,
            direction: SIMD2(1, 1),
            spacing: 0.6
        )
        bodies.append(hatchToBody(diagHatch, id: "hatch-diag",
                                   color: SIMD4(1.0, 0.5, 0.2, 1.0)))
        bodies.append(boundaryToBody(tri, id: "hatch-tri-border",
                                      color: SIMD4(0.9, 0.9, 0.9, 1.0)))

        // Hexagon boundary with vertical hatching — offset above
        let hex = makeRegularPolygon(center: SIMD2(5, 18), radius: 4, sides: 6)
        let vHatch = HatchPattern.generate(
            boundary: hex,
            direction: SIMD2(0, 1),
            spacing: 0.5
        )
        bodies.append(hatchToBody(vHatch, id: "hatch-vert",
                                   color: SIMD4(0.4, 0.9, 0.4, 1.0)))
        bodies.append(boundaryToBody(hex, id: "hatch-hex-border",
                                      color: SIMD4(0.9, 0.9, 0.9, 1.0)))

        // Cross-hatch: two directions in same boundary — offset upper right
        let crossRect: [SIMD2<Double>] = [
            SIMD2(14, 12), SIMD2(24, 12), SIMD2(24, 20), SIMD2(14, 20)
        ]
        let h1 = HatchPattern.generate(boundary: crossRect, direction: SIMD2(1, 1), spacing: 0.7)
        let h2 = HatchPattern.generate(boundary: crossRect, direction: SIMD2(1, -1), spacing: 0.7)
        bodies.append(hatchToBody(h1, id: "hatch-cross1",
                                   color: SIMD4(0.9, 0.3, 0.3, 1.0)))
        bodies.append(hatchToBody(h2, id: "hatch-cross2",
                                   color: SIMD4(0.3, 0.3, 0.9, 1.0)))
        bodies.append(boundaryToBody(crossRect, id: "hatch-cross-border",
                                      color: SIMD4(0.9, 0.9, 0.9, 1.0)))

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Hatch patterns: horizontal, 45°, vertical, cross-hatch"
        )
    }

    // MARK: - v0.29: Shape Operations

    /// Demonstrates NURBS conversion, fast sewing, and draft extrusion.
    static func shapeOperations() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Original cylinder
        if let cyl = Shape.cylinder(radius: 1.5, height: 4.0) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "op-original", color: SIMD4(0.6, 0.6, 0.6, 0.5)
            )
            if let body { bodies.append(body) }

            // NURBS-converted version — offset right
            if let nurbs = cyl.convertedToNURBS() {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    nurbs, id: "op-nurbs", color: SIMD4(0.3, 0.7, 1.0, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: 5, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        // Box + fast sewing demo: create faces and sew them
        if let box = Shape.box(width: 3, height: 2, depth: 2) {
            if let sewn = box.fastSewn() {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    sewn, id: "op-fastsewn", color: SIMD4(0.9, 0.6, 0.3, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: -5, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        // Wedge for variety — offset back
        if let wedge = Shape.wedge(dx: 3, dy: 2, dz: 3, ltx: 0.5) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                wedge, id: "op-wedge", color: SIMD4(0.5, 0.9, 0.5, 1.0)
            )
            if var body {
                offsetBody(&body, dx: 0, dy: 5, dz: 0)
                bodies.append(body)
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Shape ops: original, NURBS conversion, fast sewing, wedge"
        )
    }

    // MARK: - v0.29: Polynomial Solver

    /// Visualizes roots of polynomial equations as curves with marked roots.
    static func polynomialRoots() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Quadratic: x² - 5x + 6 = 0  →  roots at x=2, x=3
        let quadRoots = PolynomialSolver.quadratic(a: 1, b: -5, c: 6)
        let quadCurve = samplePolynomial(
            { x in x * x - 5 * x + 6 },
            xRange: -1...5, yOffset: 0
        )
        bodies.append(polylineToBody(quadCurve, id: "poly-quad",
                                      color: SIMD4(0.3, 0.6, 1.0, 1.0)))
        for (i, root) in quadRoots.roots.enumerated() {
            bodies.append(makeMarker(
                at: SIMD3<Float>(Float(root), 0, 0),
                radius: 0.15, id: "poly-quad-r\(i)",
                color: SIMD4(1.0, 0.2, 0.2, 1.0)
            ))
        }

        // Cubic: x³ - 6x² + 11x - 6 = 0  →  roots at x=1, 2, 3
        let cubicRoots = PolynomialSolver.cubic(a: 1, b: -6, c: 11, d: -6)
        let cubicCurve = samplePolynomial(
            { x in x * x * x - 6 * x * x + 11 * x - 6 },
            xRange: -0.5...4, yOffset: 8
        )
        bodies.append(polylineToBody(cubicCurve, id: "poly-cubic",
                                      color: SIMD4(0.2, 0.9, 0.3, 1.0)))
        for (i, root) in cubicRoots.roots.enumerated() {
            bodies.append(makeMarker(
                at: SIMD3<Float>(Float(root), 8, 0),
                radius: 0.15, id: "poly-cubic-r\(i)",
                color: SIMD4(1.0, 0.2, 0.2, 1.0)
            ))
        }

        // Quartic: x⁴ - 10x² + 9 = 0  →  roots at x=±1, ±3
        let quarticRoots = PolynomialSolver.quartic(a: 1, b: 0, c: -10, d: 0, e: 9)
        let quarticCurve = samplePolynomial(
            { x in x * x * x * x - 10 * x * x + 9 },
            xRange: -4...4, yOffset: 16, yScale: 0.1
        )
        bodies.append(polylineToBody(quarticCurve, id: "poly-quartic",
                                      color: SIMD4(0.9, 0.4, 0.8, 1.0)))
        for (i, root) in quarticRoots.roots.enumerated() {
            bodies.append(makeMarker(
                at: SIMD3<Float>(Float(root), 16, 0),
                radius: 0.15, id: "poly-quartic-r\(i)",
                color: SIMD4(1.0, 0.2, 0.2, 1.0)
            ))
        }

        // X axis lines for reference
        for yOff: Float in [0, 8, 16] {
            let axis: [SIMD3<Float>] = [SIMD3(-5, yOff, 0), SIMD3(5, yOff, 0)]
            bodies.append(ViewportBody(
                id: "poly-axis-\(Int(yOff))",
                vertexData: [], indices: [], edges: [axis],
                color: SIMD4(0.4, 0.4, 0.4, 0.5)
            ))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Polynomial roots: quadratic (2 roots), cubic (3), quartic (4). Red = roots."
        )
    }

    // MARK: - v0.30: Non-Uniform Scaling & Offset

    /// Demonstrates non-uniform scaling, simple offset, and fused edges.
    static func transformOps() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Original box
        if let box = Shape.box(width: 2, height: 2, depth: 2) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "xform-original", color: SIMD4(0.6, 0.6, 0.6, 0.5)
            )
            if let body { bodies.append(body) }

            // Non-uniform scale: stretch X×3, Y×0.5, Z×1.5
            if let scaled = box.nonUniformScaled(sx: 3, sy: 0.5, sz: 1.5) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    scaled, id: "xform-nuscale", color: SIMD4(0.3, 0.7, 1.0, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: 6, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        // Sphere with simple offset (inflation)
        if let sphere = Shape.sphere(radius: 1.5) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sphere, id: "xform-sphere", color: SIMD4(0.6, 0.6, 0.6, 0.5)
            )
            if var body {
                offsetBody(&body, dx: -6, dy: 0, dz: 0)
                bodies.append(body)
            }

            if let inflated = sphere.simpleOffset(by: 0.8) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    inflated, id: "xform-offset", color: SIMD4(0.9, 0.5, 0.3, 0.7)
                )
                if var body {
                    offsetBody(&body, dx: -6, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        // Cylinder with fused edges
        if let cyl = Shape.cylinder(radius: 1, height: 3) {
            // Boolean union to create extra edges, then fuse
            if let box = Shape.box(width: 1.5, height: 1.5, depth: 4) {
                if let fused = cyl.union(with: box) {
                    let (body1, _) = CADFileLoader.shapeToBodyAndMetadata(
                        fused, id: "xform-prefuse", color: SIMD4(0.7, 0.7, 0.7, 0.5)
                    )
                    if var body1 {
                        offsetBody(&body1, dx: 0, dy: 6, dz: 0)
                        bodies.append(body1)
                    }

                    if let cleaned = fused.fusedEdges() {
                        let (body2, _) = CADFileLoader.shapeToBodyAndMetadata(
                            cleaned, id: "xform-fusededges", color: SIMD4(0.5, 0.9, 0.5, 1.0)
                        )
                        if var body2 {
                            offsetBody(&body2, dx: 5, dy: 6, dz: 0)
                            bodies.append(body2)
                        }
                    }
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.30: Non-uniform scale (blue), offset (orange), fused edges (green)"
        )
    }

    // MARK: - v0.30: Shape Analysis & Canonical Recognition

    /// Demonstrates shape contents census and canonical form recognition.
    static func shapeAnalysis() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Cylinder — should recognize as canonical cylinder
        if let cyl = Shape.cylinder(radius: 2, height: 4) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "analysis-cyl", color: SIMD4(0.3, 0.6, 1.0, 1.0)
            )
            if let body { bodies.append(body) }

            let c = cyl.contents
            descriptions.append("Cyl: \(c.faces)F \(c.edges)E \(c.vertices)V")
            if let canon = cyl.recognizeCanonical() {
                descriptions.append("→ \(canon.type) r=\(String(format: "%.1f", canon.radius))")
            }
        }

        // Sphere
        if let sph = Shape.sphere(radius: 1.5) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sph, id: "analysis-sph", color: SIMD4(0.3, 0.9, 0.4, 1.0)
            )
            if var body {
                offsetBody(&body, dx: 6, dy: 0, dz: 0)
                bodies.append(body)
            }

            let c = sph.contents
            descriptions.append("Sph: \(c.faces)F \(c.edges)E")
            if let canon = sph.recognizeCanonical() {
                descriptions.append("→ \(canon.type) r=\(String(format: "%.1f", canon.radius))")
            }
        }

        // Box — should recognize planes
        if let box = Shape.box(width: 3, height: 2, depth: 2) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "analysis-box", color: SIMD4(0.9, 0.6, 0.3, 1.0)
            )
            if var body {
                offsetBody(&body, dx: -6, dy: 0, dz: 0)
                bodies.append(body)
            }

            let c = box.contents
            descriptions.append("Box: \(c.solids)S \(c.faces)F \(c.edges)E \(c.vertices)V")
        }

        // Cone
        if let cone = Shape.cone(bottomRadius: 2, topRadius: 0.5, height: 3) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                cone, id: "analysis-cone", color: SIMD4(0.8, 0.4, 0.8, 1.0)
            )
            if var body {
                offsetBody(&body, dx: 0, dy: 6, dz: 0)
                bodies.append(body)
            }

            let c = cone.contents
            descriptions.append("Cone: \(c.faces)F \(c.edges)E")
            if let canon = cone.recognizeCanonical() {
                descriptions.append("→ \(canon.type)")
            }
        }

        // Vertex primitive
        if let vtx = Shape.vertex(at: SIMD3(3, 6, 1.5)) {
            let c = vtx.contents
            descriptions.append("Vertex: \(c.vertices)V")
            // Visualize as marker
            bodies.append(makeMarker(
                at: SIMD3<Float>(3, 6, 1.5),
                radius: 0.2, id: "analysis-vtx",
                color: SIMD4(1.0, 1.0, 0.0, 1.0)
            ))
        }

        let desc = descriptions.joined(separator: " | ")
        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.30 Analysis: \(desc)"
        )
    }

    // MARK: - v0.30: Curve & Surface Intersections

    /// Demonstrates curve-curve extrema, curve-surface intersection, surface-surface intersection.
    static func intersectionAnalysis() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // -- Curve-curve extrema --
        // Two skew lines in 3D
        if let line1 = Curve3D.line(through: SIMD3(-5, 0, 0), direction: SIMD3(1, 0, 0)),
           let line2 = Curve3D.line(through: SIMD3(0, -5, 2), direction: SIMD3(0, 1, 0)) {

            // Visualize the lines
            let l1pts: [SIMD3<Float>] = [SIMD3(-5, 0, 0), SIMD3(5, 0, 0)]
            let l2pts: [SIMD3<Float>] = [SIMD3(0, -5, 2), SIMD3(0, 5, 2)]
            bodies.append(ViewportBody(id: "ix-line1", vertexData: [], indices: [], edges: [l1pts],
                                       color: SIMD4(0.3, 0.6, 1.0, 1.0)))
            bodies.append(ViewportBody(id: "ix-line2", vertexData: [], indices: [], edges: [l2pts],
                                       color: SIMD4(1.0, 0.5, 0.2, 1.0)))

            if let dist = line1.minDistance(to: line2) {
                let extrema = line1.extrema(with: line2)
                for (i, ext) in extrema.enumerated() {
                    let p1 = SIMD3<Float>(Float(ext.point1.x), Float(ext.point1.y), Float(ext.point1.z))
                    let p2 = SIMD3<Float>(Float(ext.point2.x), Float(ext.point2.y), Float(ext.point2.z))
                    bodies.append(makeMarker(at: p1, radius: 0.15, id: "ix-ext-p1-\(i)",
                                             color: SIMD4(1.0, 0.2, 0.2, 1.0)))
                    bodies.append(makeMarker(at: p2, radius: 0.15, id: "ix-ext-p2-\(i)",
                                             color: SIMD4(0.2, 1.0, 0.2, 1.0)))
                    // Connector line between closest points
                    bodies.append(ViewportBody(id: "ix-ext-conn-\(i)", vertexData: [], indices: [], edges: [[p1, p2]],
                                               color: SIMD4(1.0, 1.0, 0.0, 1.0)))
                }
                _ = dist  // used for the description
            }
        }

        // -- Curve-surface intersection --
        // Circle curve intersecting a plane
        if let circle = Curve3D.circle(center: SIMD3(0, 0, 0), normal: SIMD3(1, 0, 1), radius: 3),
           let plane = Surface.plane(origin: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1)) {

            // Visualize the circle using evaluate
            let cParams = uniformParameters(curve: circle, count: 80)
            let pts = circle.evaluateGrid(cParams)
            if !pts.isEmpty {
                let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
                var closed = floatPts
                if let first = closed.first { closed.append(first) }
                bodies.append(ViewportBody(id: "ix-circle", vertexData: [], indices: [], edges: [closed],
                                           color: SIMD4(0.5, 0.8, 1.0, 1.0)))
            }

            // Visualize the plane as a flat quad
            let planeSize: Float = 5
            let planeVerts: [SIMD3<Float>] = [
                SIMD3(-planeSize, -planeSize, 0), SIMD3(planeSize, -planeSize, 0),
                SIMD3(planeSize, planeSize, 0), SIMD3(-planeSize, planeSize, 0),
                SIMD3(-planeSize, -planeSize, 0)
            ]
            bodies.append(ViewportBody(id: "ix-plane", vertexData: [], indices: [], edges: [planeVerts],
                                       color: SIMD4(0.5, 0.5, 0.5, 0.3)))

            let hits = circle.intersections(with: plane)
            for (i, hit) in hits.enumerated() {
                let p = SIMD3<Float>(Float(hit.point.x), Float(hit.point.y), Float(hit.point.z))
                bodies.append(makeMarker(at: p, radius: 0.2, id: "ix-cs-hit-\(i)",
                                         color: SIMD4(1.0, 0.3, 0.3, 1.0)))
            }
        }

        // -- Surface-surface intersection --
        // Cylinder intersecting a sphere
        if let cylSurf = Surface.cylinder(origin: .zero, axis: SIMD3(0, 0, 1), radius: 2),
           let sphSurf = Surface.sphere(center: SIMD3(1, 0, 0), radius: 2.5) {

            // Show the shapes for context
            if let cylShape = Shape.cylinder(radius: 2, height: 4) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    cylShape, id: "ix-cyl-shape", color: SIMD4(0.3, 0.6, 1.0, 0.3)
                )
                if var body {
                    offsetBody(&body, dx: 12, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
            if let sphShape = Shape.sphere(radius: 2.5) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    sphShape, id: "ix-sph-shape", color: SIMD4(0.3, 0.9, 0.4, 0.3)
                )
                if var body {
                    offsetBody(&body, dx: 13, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }

            let ixCurves = cylSurf.intersections(with: sphSurf)
            for (i, curve) in ixCurves.enumerated() {
                let ssParams = uniformParameters(curve: curve, count: 100)
                let pts = curve.evaluateGrid(ssParams)
                if !pts.isEmpty {
                    let floatPts = pts.map { SIMD3<Float>(Float($0.x) + 12, Float($0.y), Float($0.z)) }
                    bodies.append(ViewportBody(id: "ix-ss-\(i)", vertexData: [], indices: [], edges: [floatPts],
                                               color: SIMD4(1.0, 0.2, 0.2, 1.0)))
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.30 Intersections: curve-curve extrema, curve-surface hits, surface-surface curves"
        )
    }

    // MARK: - v0.30: Volume & Connected Shapes

    /// Demonstrates makeVolume from faces and makeConnected.
    static func volumeOps() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Make a volume from overlapping boxes
        if let box1 = Shape.box(width: 3, height: 3, depth: 3),
           let box2 = Shape.box(width: 3, height: 3, depth: 3)?.translated(by: SIMD3(1.5, 1.5, 0)) {

            // Show originals semi-transparent
            let (b1, _) = CADFileLoader.shapeToBodyAndMetadata(
                box1, id: "vol-box1", color: SIMD4(0.3, 0.6, 1.0, 0.3)
            )
            if let b1 { bodies.append(b1) }
            let (b2, _) = CADFileLoader.shapeToBodyAndMetadata(
                box2, id: "vol-box2", color: SIMD4(1.0, 0.5, 0.2, 0.3)
            )
            if let b2 { bodies.append(b2) }

            // Volume from faces
            if let volume = Shape.makeVolume(from: [box1, box2]) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    volume, id: "vol-result", color: SIMD4(0.5, 0.9, 0.5, 0.8)
                )
                if var body {
                    offsetBody(&body, dx: 8, dy: 0, dz: 0)
                    bodies.append(body)
                }

                let c = volume.contents
                bodies.append(contentsOf: []) // no-op; just use c below
                _ = c // description will reference it
            }
        }

        // MakeConnected — two adjacent boxes sharing a face
        if let box1 = Shape.box(width: 2, height: 2, depth: 2),
           let box2 = Shape.box(width: 2, height: 2, depth: 2)?.translated(by: SIMD3(2, 0, 0)) {

            let (b1, _) = CADFileLoader.shapeToBodyAndMetadata(
                box1, id: "conn-box1", color: SIMD4(0.7, 0.3, 0.8, 0.5)
            )
            if var b1 {
                offsetBody(&b1, dx: 0, dy: 8, dz: 0)
                bodies.append(b1)
            }
            let (b2, _) = CADFileLoader.shapeToBodyAndMetadata(
                box2, id: "conn-box2", color: SIMD4(0.3, 0.8, 0.7, 0.5)
            )
            if var b2 {
                offsetBody(&b2, dx: 0, dy: 8, dz: 0)
                bodies.append(b2)
            }

            if let connected = Shape.makeConnected([box1, box2]) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    connected, id: "conn-result", color: SIMD4(0.9, 0.8, 0.3, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: 8, dy: 8, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.30: makeVolume (green) from overlapping boxes, makeConnected (yellow)"
        )
    }

    // MARK: - v0.31: Quasi-Uniform Curve Sampling

    /// Compares uniform vs quasi-uniform (arc-length) sampling on curves.
    static func quasiUniformSampling() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a BSpline curve with varying curvature
        if let curve = Curve3D.bezier(poles: [
            SIMD3(0, 0, 0), SIMD3(2, 5, 0), SIMD3(5, -3, 2),
            SIMD3(8, 4, 1), SIMD3(12, 0, 0), SIMD3(15, 2, -1)
        ]) {
            // Draw the full curve
            let fullParams = uniformParameters(curve: curve, count: 200)
            let fullPts = curve.evaluateGrid(fullParams)
            let floatFull = fullPts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            bodies.append(ViewportBody(id: "qu-curve", vertexData: [], indices: [], edges: [floatFull],
                                       color: SIMD4(0.5, 0.5, 0.5, 0.5)))

            // Uniform parametric sampling (20 points) — clustered in low-curvature areas
            let uniParams = uniformParameters(curve: curve, count: 20)
            let uniPts = curve.evaluateGrid(uniParams)
            for (i, pt) in uniPts.enumerated() {
                bodies.append(makeMarker(
                    at: SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z)),
                    radius: 0.15, id: "qu-uni-\(i)",
                    color: SIMD4(1.0, 0.3, 0.3, 1.0)
                ))
            }

            // Quasi-uniform arc-length sampling (20 points) — evenly spaced along curve
            let quParams = curve.quasiUniformParameters(count: 20)
            let quPts = curve.evaluateGrid(quParams)
            for (i, pt) in quPts.enumerated() {
                bodies.append(makeMarker(
                    at: SIMD3<Float>(Float(pt.x), Float(pt.y) - 8, Float(pt.z)),
                    radius: 0.15, id: "qu-arc-\(i)",
                    color: SIMD4(0.3, 1.0, 0.3, 1.0)
                ))
            }

            // Draw the offset copy for arc-length sampling
            let offsetFull = fullPts.map { SIMD3<Float>(Float($0.x), Float($0.y) - 8, Float($0.z)) }
            bodies.append(ViewportBody(id: "qu-curve2", vertexData: [], indices: [], edges: [offsetFull],
                                       color: SIMD4(0.5, 0.5, 0.5, 0.5)))

            // Deflection-based sampling
            let deflPts = curve.quasiUniformDeflectionPoints(deflection: 0.5)
            for (i, pt) in deflPts.enumerated() {
                bodies.append(makeMarker(
                    at: SIMD3<Float>(Float(pt.x), Float(pt.y) - 16, Float(pt.z)),
                    radius: 0.12, id: "qu-defl-\(i)",
                    color: SIMD4(0.3, 0.5, 1.0, 1.0)
                ))
            }
            let offsetFull2 = fullPts.map { SIMD3<Float>(Float($0.x), Float($0.y) - 16, Float($0.z)) }
            bodies.append(ViewportBody(id: "qu-curve3", vertexData: [], indices: [], edges: [offsetFull2],
                                       color: SIMD4(0.5, 0.5, 0.5, 0.5)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Sampling: uniform-param (red, top) vs arc-length (green, mid) vs deflection (blue, bottom)"
        )
    }

    // MARK: - v0.31: Bezier Surface Fill

    /// Creates surfaces from boundary curves using different fill styles.
    static func bezierSurfaceFill() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Define 4 boundary curves forming a twisted quad
        guard let c1 = Curve3D.bezier(poles: [SIMD3(0, 0, 0), SIMD3(3, 0, 1), SIMD3(6, 0, 0)]),
              let c2 = Curve3D.bezier(poles: [SIMD3(6, 0, 0), SIMD3(6, 3, 2), SIMD3(6, 6, 0)]),
              let c3 = Curve3D.bezier(poles: [SIMD3(6, 6, 0), SIMD3(3, 6, -1), SIMD3(0, 6, 0)]),
              let c4 = Curve3D.bezier(poles: [SIMD3(0, 6, 0), SIMD3(0, 3, 1.5), SIMD3(0, 0, 0)])
        else {
            return Curve2DGallery.GalleryResult(bodies: bodies, description: "Curve creation failed")
        }

        // Draw boundary curves
        for (i, curve) in [c1, c2, c3, c4].enumerated() {
            let params = uniformParameters(curve: curve, count: 50)
            let pts = curve.evaluateGrid(params)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            bodies.append(ViewportBody(id: "bf-edge-\(i)", vertexData: [], indices: [], edges: [floatPts],
                                       color: SIMD4(1.0, 1.0, 1.0, 1.0)))
        }

        // Stretch fill
        if let surf = Surface.bezierFill(c1, c2, c3, c4, style: .stretch),
           let shell = Shape.shell(from: surf) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                shell, id: "bf-stretch", color: SIMD4(0.3, 0.6, 1.0, 0.8),
                deflection: 0.01
            )
            if let body { bodies.append(body) }
        }

        // Coons fill — offset right
        if let surf = Surface.bezierFill(c1, c2, c3, c4, style: .coons),
           let shell = Shape.shell(from: surf) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                shell, id: "bf-coons", color: SIMD4(0.3, 0.9, 0.4, 0.8),
                deflection: 0.01
            )
            if var body {
                offsetBody(&body, dx: 10, dy: 0, dz: 0)
                bodies.append(body)
            }
        }

        // Curved fill — offset further right
        if let surf = Surface.bezierFill(c1, c2, c3, c4, style: .curved),
           let shell = Shape.shell(from: surf) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                shell, id: "bf-curved", color: SIMD4(0.9, 0.5, 0.3, 0.8),
                deflection: 0.01
            )
            if var body {
                offsetBody(&body, dx: 20, dy: 0, dz: 0)
                bodies.append(body)
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Bezier fill: stretch (blue), coons (green), curved (orange). Same boundary, 3 styles."
        )
    }

    // MARK: - v0.31: Revolution from Curve

    /// Creates solids of revolution from different meridian curves.
    static func revolutionDemo() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Wine glass profile: BSpline meridian
        if let profile = Curve3D.bezier(poles: [
            SIMD3(0.5, 0, 0), SIMD3(1.5, 0, 0), SIMD3(0.3, 0, 2),
            SIMD3(0.2, 0, 3), SIMD3(0.8, 0, 4), SIMD3(1.5, 0, 4.5)
        ]) {
            if let glass = Shape.revolution(meridian: profile) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    glass, id: "rev-glass", color: SIMD4(0.4, 0.7, 1.0, 0.8),
                    deflection: 0.01
                )
                if let body { bodies.append(body) }
            }

            // Show the meridian curve
            let params = uniformParameters(curve: profile, count: 100)
            let pts = profile.evaluateGrid(params)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            bodies.append(ViewportBody(id: "rev-meridian1", vertexData: [], indices: [], edges: [floatPts],
                                       color: SIMD4(1.0, 1.0, 0.0, 1.0)))
        }

        // Vase profile
        if let profile = Curve3D.bezier(poles: [
            SIMD3(1.0, 0, 0), SIMD3(2.0, 0, 1), SIMD3(0.8, 0, 3),
            SIMD3(1.5, 0, 5), SIMD3(1.2, 0, 6)
        ]) {
            if let vase = Shape.revolution(meridian: profile) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    vase, id: "rev-vase", color: SIMD4(0.9, 0.5, 0.3, 0.8),
                    deflection: 0.01
                )
                if var body {
                    offsetBody(&body, dx: 8, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        // Partial revolution (half turn) of a line segment — creates a cone
        if let seg = Curve3D.segment(from: SIMD3(1, 0, 0), to: SIMD3(2, 0, 4)) {
            if let half = Shape.revolution(
                meridian: seg,
                axisOrigin: SIMD3(0, 0, 0),
                axisDirection: SIMD3(0, 0, 1),
                angle: .pi
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    half, id: "rev-half", color: SIMD4(0.5, 0.9, 0.5, 0.8),
                    deflection: 0.01
                )
                if var body {
                    offsetBody(&body, dx: -6, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Revolution from curves: wine glass (blue), vase (orange), half-turn (green)"
        )
    }

    // MARK: - v0.31: Linear Rib Feature

    /// Adds reinforcing ribs to a base shape.
    static func linearRibDemo() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var ribSuccess = false

        // Base plate — box(width:height:depth:) is centered at origin
        // width=10 → X: -5..5, height=2 → Y: -1..1, depth=8 → Z: -4..4
        // Top face is at Y=1
        if let plate = Shape.box(width: 10, height: 2, depth: 8) {
            // Show original
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                plate, id: "rib-base", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if let body { bodies.append(body) }

            // Rib profile: a line on the top face (Y=1), running along X
            // direction = extrusion up (Y+), draftDirection = along Z
            if let ribProfile = Wire.line(
                from: SIMD3(-4, 1, 0),
                to: SIMD3(4, 1, 0)
            ) {
                if let ribbed = plate.addingLinearRib(
                    profile: ribProfile,
                    direction: SIMD3(0, 1, 0),
                    draftDirection: SIMD3(0, 0, 1),
                    fuse: true
                ) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        ribbed, id: "rib-result", color: SIMD4(0.3, 0.7, 1.0, 1.0),
                        deflection: 0.02
                    )
                    if var body {
                        offsetBody(&body, dx: 14, dy: 0, dz: 0)
                        bodies.append(body)
                        ribSuccess = true
                    }
                }
            }

            // Fallback: if rib failed, simulate by unioning a thin box onto the plate
            if !ribSuccess {
                if let rib = Shape.box(width: 8, height: 2, depth: 0.5) {
                    if let ribMoved = rib.translated(by: SIMD3(0, 2, 0)),
                       let ribbed = plate.union(with: ribMoved) {
                        let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                            ribbed, id: "rib-fallback", color: SIMD4(0.3, 0.7, 1.0, 1.0),
                            deflection: 0.02
                        )
                        if var body {
                            offsetBody(&body, dx: 14, dy: 0, dz: 0)
                            bodies.append(body)
                        }
                    }
                }
            }
        }

        let desc = ribSuccess
            ? "v0.31 Linear rib: base plate (gray) → with rib (blue)"
            : "v0.31 Linear rib: base plate (gray) + extruded prism fallback (blue)"
        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: desc
        )
    }

    // MARK: - v0.32: Asymmetric Chamfer

    /// Demonstrates two-distance and distance-angle chamfer modes.
    static func asymmetricChamfer() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Base box for chamfering
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            // Original for reference
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "cham-original", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if let body { bodies.append(body) }

            // Two-distance chamfer on edge 0 (asymmetric: 0.8 on one side, 0.3 on the other)
            if let chamfered = box.chamferedTwoDistances([(edgeIndex: 0, faceIndex: 0, dist1: 0.8, dist2: 0.3)]) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    chamfered, id: "cham-twodist", color: SIMD4(0.3, 0.7, 1.0, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: 7, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }

            // Distance-angle chamfer on edge 2 (distance=0.5, angle=30°)
            if let chamfered = box.chamferedDistAngle([(edgeIndex: 2, faceIndex: 0, distance: 0.5, angleDegrees: 30)]) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    chamfered, id: "cham-distangle", color: SIMD4(0.9, 0.5, 0.3, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.32 Chamfers: original (gray), two-distance (blue), dist+angle (orange)"
        )
    }

    // MARK: - v0.32: Loft Advanced

    /// Demonstrates ruled loft and vertex-tipped loft (cone).
    static func loftAdvanced() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Circle at origin in XY, second circle offset to Z=5
        if let circle1 = Wire.circle(radius: 2.0),
           let circle2 = Wire.circle(radius: 1.0)?.offset3D(distance: 5, direction: SIMD3(0, 0, 1)) {

            // Ruled loft (straight line segments between profiles)
            if let ruled = Shape.loft(profiles: [circle1, circle2], solid: true, ruled: true) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    ruled, id: "loft-ruled", color: SIMD4(0.3, 0.7, 1.0, 0.9)
                )
                if let body { bodies.append(body) }
            }

            // Smooth loft (B-spline interpolation)
            if let smooth = Shape.loft(profiles: [circle1, circle2], solid: true, ruled: false) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    smooth, id: "loft-smooth", color: SIMD4(0.3, 0.9, 0.4, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 7, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }

            // Vertex-tipped loft (cone: circle to a point)
            if let cone = Shape.loft(profiles: [circle1], solid: true, ruled: true,
                                     lastVertex: SIMD3(0, 0, 6)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    cone, id: "loft-cone", color: SIMD4(0.9, 0.5, 0.3, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.32 Loft: ruled (blue), smooth B-spline (green), vertex-tip cone (orange)"
        )
    }

    // MARK: - v0.32: Offset by Join

    /// Demonstrates offset with different join types.
    static func offsetByJoin() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // L-shaped base: box + box union
        if let box1 = Shape.box(width: 4, height: 2, depth: 2),
           let box2 = Shape.box(width: 2, height: 4, depth: 2),
           let lShape = box1.union(with: box2) {

            // Original
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                lShape, id: "off-original", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if let body { bodies.append(body) }

            // Arc join (smooth rounded gaps)
            if let arc = lShape.offset(by: 0.3, joinType: .arc) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    arc, id: "off-arc", color: SIMD4(0.3, 0.7, 1.0, 0.8)
                )
                if var body {
                    offsetBody(&body, dx: 8, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }

            // Intersection join (sharp edges at gaps)
            if let inter = lShape.offset(by: 0.3, joinType: .intersection) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    inter, id: "off-intersection", color: SIMD4(0.9, 0.5, 0.3, 0.8)
                )
                if var body {
                    offsetBody(&body, dx: 16, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.32 Offset: original (gray), arc join (blue), intersection join (orange)"
        )
    }

    // MARK: - v0.32: Draft Prism & Revolved Feature

    /// Demonstrates draft prism (tapered extrusion) and revolved feature on a base shape.
    static func featureOps() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Base box for features
        if let box = Shape.box(width: 6, height: 2, depth: 6) {
            // Show base
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "feat-base", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if let body { bodies.append(body) }

            // Draft prism: tapered boss on top face (Y=1)
            // Profile rectangle on the top face using 3D path
            if let profile = Wire.path([
                SIMD3(-1, 1, -1), SIMD3(1, 1, -1),
                SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
            ], closed: true) {
                if let drafted = box.addingDraftPrism(
                    profile: profile, sketchFaceIndex: 2,
                    draftAngle: 10, height: 3, fuse: true
                ) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        drafted, id: "feat-draftprism", color: SIMD4(0.3, 0.7, 1.0, 1.0)
                    )
                    if var body {
                        offsetBody(&body, dx: 10, dy: 0, dz: 0)
                        bodies.append(body)
                    }
                }
            }

            // Revolved feature: groove cut around Y axis
            // Profile in XY plane, offset from center
            if let profile = Wire.path([
                SIMD3(2.5, 1, -0.25), SIMD3(3.5, 1, -0.25),
                SIMD3(3.5, 1, 0.25), SIMD3(2.5, 1, 0.25)
            ], closed: true) {
                if let revolved = box.addingRevolvedFeature(
                    profile: profile, sketchFaceIndex: 2,
                    axisOrigin: SIMD3(0, 0, 0),
                    axisDirection: SIMD3(0, 1, 0),
                    angle: 360, fuse: false
                ) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        revolved, id: "feat-revolved", color: SIMD4(0.9, 0.5, 0.3, 1.0)
                    )
                    if var body {
                        offsetBody(&body, dx: 20, dy: 0, dz: 0)
                        bodies.append(body)
                    }
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.32 Features: base (gray), draft prism boss (blue), revolved groove (orange)"
        )
    }

    // MARK: - v0.33: Pipe Shell Transitions

    /// Demonstrates pipe shell with different transition modes at spine corners.
    static func pipeTransitions() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // L-shaped spine with a corner
        if let spine = Wire.path([
            SIMD3(0, 0, 0), SIMD3(4, 0, 0), SIMD3(4, 4, 0)
        ]),
           let profile = Wire.circle(radius: 0.5) {

            // Transformed (smooth)
            if let smooth = Shape.pipeShellWithTransition(
                spine: spine, profile: profile, transition: .transformed
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    smooth, id: "pipe-transformed", color: SIMD4(0.3, 0.7, 1.0, 0.9)
                )
                if let body { bodies.append(body) }
            }

            // Right corner (sharp)
            if let sharp = Shape.pipeShellWithTransition(
                spine: spine, profile: profile, transition: .rightCorner
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    sharp, id: "pipe-right", color: SIMD4(0.9, 0.5, 0.3, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 8, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }

            // Round corner (filleted)
            if let round = Shape.pipeShellWithTransition(
                spine: spine, profile: profile, transition: .roundCorner
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    round, id: "pipe-round", color: SIMD4(0.3, 0.9, 0.4, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 16, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.33 Pipe transitions: smooth (blue), sharp corner (orange), round corner (green)"
        )
    }

    // MARK: - v0.33: Face from Surface

    /// Demonstrates creating faces from parametric surfaces and edges-to-faces.
    static func faceFromSurface() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Face from cylindrical surface with bounded UV
        if let cylSurf = Surface.cylinder(origin: .zero, axis: SIMD3(0, 0, 1), radius: 2.0) {
            // Partial cylinder face (half-turn, height 0..4)
            if let face = cylSurf.toFace(uRange: 0...Double.pi, vRange: 0...4) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    face, id: "face-cyl", color: SIMD4(0.3, 0.7, 1.0, 0.9),
                    deflection: 0.02
                )
                if let body { bodies.append(body) }
            }
        }

        // Face from spherical surface with bounded UV
        if let sphSurf = Surface.sphere(center: SIMD3(0, 0, 0), radius: 2.0) {
            // Quarter sphere
            if let face = sphSurf.toFace(
                uRange: 0...(Double.pi / 2),
                vRange: 0...(Double.pi / 2)
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    face, id: "face-sph", color: SIMD4(0.3, 0.9, 0.4, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 7, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        // Face from a plane surface
        if let planeSurf = Surface.plane(origin: .zero, normal: SIMD3(0, 0, 1)) {
            if let face = planeSurf.toFace(uRange: -3...3, vRange: -2...2) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    face, id: "face-plane", color: SIMD4(0.9, 0.5, 0.3, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.33 Face from surface: half cylinder (blue), quarter sphere (green), bounded plane (orange)"
        )
    }

    // MARK: - v0.34: Section Curves & Boolean Validation

    /// Demonstrates shape-to-shape section and boolean pre-validation.
    static func sectionAndValidation() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Two intersecting shapes: cylinder through a box
        if let box = Shape.box(width: 4, height: 4, depth: 4),
           let cyl = Shape.cylinder(radius: 1.5, height: 6)?.translated(by: SIMD3(0, -3, 0)) {

            // Show both shapes semi-transparent
            let (b1, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "sec-box", color: SIMD4(0.3, 0.6, 1.0, 0.3)
            )
            if let b1 { bodies.append(b1) }
            let (b2, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "sec-cyl", color: SIMD4(0.9, 0.5, 0.3, 0.3),
                deflection: 0.02
            )
            if let b2 { bodies.append(b2) }

            // Section: intersection curves
            if let section = box.section(with: cyl) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    section, id: "sec-curves", color: SIMD4(1.0, 0.2, 0.2, 1.0),
                    deflection: 0.02
                )
                if let body { bodies.append(body) }
                let c = section.contents
                descriptions.append("Section: \(c.edges)E")
            }

            // Boolean pre-validation
            let boxValid = box.isValidForBoolean
            let cylValid = cyl.isValidForBoolean
            let pairValid = box.isValidForBoolean(with: cyl)
            descriptions.append("Valid: box=\(boxValid), cyl=\(cylValid), pair=\(pairValid)")
        }

        // Second example: sphere slicing through a box — offset right
        if let box2 = Shape.box(width: 3, height: 3, depth: 3),
           let sph = Shape.sphere(radius: 2.5)?.translated(by: SIMD3(1.5, 1.5, 0)) {
            let (b1, _) = CADFileLoader.shapeToBodyAndMetadata(
                box2, id: "sec-box2", color: SIMD4(0.3, 0.9, 0.4, 0.3)
            )
            if var b1 {
                offsetBody(&b1, dx: 10, dy: 0, dz: 0)
                bodies.append(b1)
            }
            let (b2, _) = CADFileLoader.shapeToBodyAndMetadata(
                sph, id: "sec-sph", color: SIMD4(0.8, 0.4, 0.8, 0.3),
                deflection: 0.02
            )
            if var b2 {
                offsetBody(&b2, dx: 10, dy: 0, dz: 0)
                bodies.append(b2)
            }

            if let section = box2.section(with: sph) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    section, id: "sec-curves2", color: SIMD4(1.0, 1.0, 0.0, 1.0),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 10, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.34 Section: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.34: Shape Repair (Split by Angle, Drop Small Edges)

    /// Demonstrates split-by-angle and drop-small-edges repair operations.
    static func shapeRepair() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Full cylinder — surfaces span 360°
        if let cyl = Shape.cylinder(radius: 2, height: 4) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "repair-cyl", color: SIMD4(0.6, 0.6, 0.6, 0.5),
                deflection: 0.02
            )
            if let body { bodies.append(body) }

            let origContents = cyl.contents

            // Split by angle: 90° — turns full cylinder into quarter-cylinders
            if let split = cyl.splitByAngle(90) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    split, id: "repair-split90", color: SIMD4(0.3, 0.7, 1.0, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 7, dy: 0, dz: 0)
                    bodies.append(body)
                }

                let splitContents = split.contents
                _ = (origContents, splitContents) // used in description
            }
        }

        // Sphere — split by 90° creates octant patches
        if let sph = Shape.sphere(radius: 2) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sph, id: "repair-sph", color: SIMD4(0.6, 0.6, 0.6, 0.5),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 0, dy: 7, dz: 0)
                bodies.append(body)
            }

            if let split = sph.splitByAngle(90) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    split, id: "repair-sphsplit", color: SIMD4(0.9, 0.5, 0.3, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 7, dy: 7, dz: 0)
                    bodies.append(body)
                }
            }
        }

        // Drop small edges demo: create a shape with tiny edges then clean
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            // Fillet with a very small radius to create tiny edges
            if let filleted = box.filleted(radius: 0.01) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    filleted, id: "repair-tiny", color: SIMD4(0.6, 0.6, 0.6, 0.5)
                )
                if var body {
                    offsetBody(&body, dx: 0, dy: 14, dz: 0)
                    bodies.append(body)
                }

                if let cleaned = filleted.droppingSmallEdges(tolerance: 0.05) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        cleaned, id: "repair-cleaned", color: SIMD4(0.3, 0.9, 0.4, 0.9)
                    )
                    if var body {
                        offsetBody(&body, dx: 7, dy: 14, dz: 0)
                        bodies.append(body)
                    }
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.34 Repair: splitByAngle 90° (blue/orange), dropSmallEdges (green)"
        )
    }

    // MARK: - v0.34: Multi-Fuse

    /// Demonstrates fuseAll vs sequential union for multiple shapes.
    static func multiFuse() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create 4 overlapping cylinders in a cross pattern
        let shapes: [(Shape, SIMD3<Double>)] = {
            var result: [(Shape, SIMD3<Double>)] = []
            if let c1 = Shape.cylinder(radius: 1, height: 6) {
                result.append((c1, .zero))
            }
            if let c2 = Shape.cylinder(radius: 1, height: 6)?.rotated(axis: SIMD3(1, 0, 0), angle: .pi / 2) {
                result.append((c2, .zero))
            }
            if let c3 = Shape.cylinder(radius: 1, height: 6)?.rotated(axis: SIMD3(0, 1, 0), angle: .pi / 2) {
                result.append((c3, .zero))
            }
            if let c4 = Shape.cylinder(radius: 0.8, height: 6)?.rotated(axis: SIMD3(1, 1, 0), angle: .pi / 4) {
                result.append((c4, .zero))
            }
            return result
        }()

        // Show individual cylinders semi-transparent
        let colors: [SIMD4<Float>] = [
            SIMD4(0.3, 0.6, 1.0, 0.2), SIMD4(0.9, 0.5, 0.3, 0.2),
            SIMD4(0.3, 0.9, 0.4, 0.2), SIMD4(0.8, 0.4, 0.8, 0.2)
        ]
        for (i, (shape, _)) in shapes.enumerated() {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                shape, id: "fuse-orig-\(i)", color: colors[i],
                deflection: 0.02
            )
            if let body { bodies.append(body) }
        }

        // fuseAll — simultaneous multi-tool boolean
        let allShapes = shapes.map { $0.0 }
        if let fused = Shape.fuseAll(allShapes) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                fused, id: "fuse-all", color: SIMD4(0.3, 0.7, 1.0, 0.9),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 10, dy: 0, dz: 0)
                bodies.append(body)
            }

            let c = fused.contents
            _ = c
        }

        // Sequential union for comparison
        var seqResult: Shape? = allShapes.first
        for shape in allShapes.dropFirst() {
            seqResult = seqResult?.union(with: shape)
        }
        if let seq = seqResult {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                seq, id: "fuse-seq", color: SIMD4(0.9, 0.5, 0.3, 0.9),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 20, dy: 0, dz: 0)
                bodies.append(body)
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.34 Multi-fuse: originals (left), fuseAll (blue), sequential union (orange)"
        )
    }

    // MARK: - v0.34: Split Face by Wire

    /// Demonstrates imprinting a wire onto a face to split it.
    static func splitFaceByWire() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Box with a wire imprinted on a face
        if let box = Shape.box(width: 6, height: 4, depth: 4) {
            // Show original
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "split-original", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if let body { bodies.append(body) }

            let origContents = box.contents

            // Create a wire on the top face (Y=2) — a diagonal line
            if let wire = Wire.line(from: SIMD3(-2, 2, -1), to: SIMD3(2, 2, 1)) {
                // Top face index varies by OCCT internals; try face 2 (commonly the top)
                for faceIdx in 0..<origContents.faces {
                    if let split = box.splittingFace(with: wire, faceIndex: faceIdx) {
                        let splitContents = split.contents
                        // Successfully split if face count increased
                        if splitContents.faces > origContents.faces {
                            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                                split, id: "split-result", color: SIMD4(0.3, 0.7, 1.0, 1.0)
                            )
                            if var body {
                                offsetBody(&body, dx: 10, dy: 0, dz: 0)
                                bodies.append(body)
                            }
                            break
                        }
                    }
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.34 Split face: original (gray), face split by wire imprint (blue)"
        )
    }

    // MARK: - v0.35: Cylindrical Projection & Multi-Offset

    /// Demonstrates cylindrical wire projection onto a surface and multi-offset wires.
    static func projectionAndOffset() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Cylindrical projection: project a circle wire onto a sphere
        if let sphere = Shape.sphere(radius: 3),
           let circleWire = Wire.circle(radius: 2),
           let circleShape = Shape.fromWire(circleWire) {

            // Show the sphere
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sphere, id: "proj-sphere", color: SIMD4(0.6, 0.6, 0.6, 0.4),
                deflection: 0.02
            )
            if let body { bodies.append(body) }

            // Project circle onto sphere along Z
            if let projected = Shape.projectWire(circleShape, onto: sphere,
                                                  direction: SIMD3(0, 0, 1)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    projected, id: "proj-result", color: SIMD4(1.0, 0.2, 0.2, 1.0),
                    deflection: 0.02
                )
                if let body { bodies.append(body) }
            }
        }

        // Multi-offset wires from a face
        if let box = Shape.box(width: 6, height: 0.1, depth: 6) {
            // Show the face
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "moff-face", color: SIMD4(0.5, 0.5, 0.5, 0.3)
            )
            if var body {
                offsetBody(&body, dx: 10, dy: 0, dz: 0)
                bodies.append(body)
            }

            // Generate concentric offset wires (like CNC toolpaths)
            let offsets = box.multiOffsetWires(offsets: [-0.5, -1.0, -1.5, -2.0, -2.5])
            let offsetColors: [SIMD4<Float>] = [
                SIMD4(0.3, 0.7, 1.0, 1.0), SIMD4(0.3, 0.9, 0.4, 1.0),
                SIMD4(0.9, 0.5, 0.3, 1.0), SIMD4(0.8, 0.4, 0.8, 1.0),
                SIMD4(1.0, 0.8, 0.2, 1.0)
            ]
            for (i, wire) in offsets.enumerated() {
                var wireBody = wireToBody(wire, id: "moff-\(i)",
                                          color: offsetColors[i % offsetColors.count])
                offsetBody(&wireBody, dx: 10, dy: 0, dz: 0)
                bodies.append(wireBody)
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.35: Wire projection onto sphere (red), multi-offset toolpaths (right)"
        )
    }

    // MARK: - v0.36: Face Division & Conical Projection

    /// Demonstrates face subdivision and conical (point-source) projection.
    static func faceDivision() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Face division: split cylinder faces into patches
        if let cyl = Shape.cylinder(radius: 2, height: 4) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "div-orig", color: SIMD4(0.6, 0.6, 0.6, 0.5),
                deflection: 0.02
            )
            if let body { bodies.append(body) }

            // Divide into ~4 patches per face
            if let divided = cyl.dividedByNumber(4) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    divided, id: "div-result", color: SIMD4(0.3, 0.7, 1.0, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 7, dy: 0, dz: 0)
                    bodies.append(body)
                }

                let origC = cyl.contents
                let divC = divided.contents
                _ = (origC, divC)
            }
        }

        // Conical projection: project circle from a point onto a box
        if let box = Shape.box(width: 6, height: 6, depth: 1),
           let circleWire = Wire.circle(radius: 1.5),
           let circleShape = Shape.fromWire(circleWire) {

            let (b, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "cone-box", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if var b {
                offsetBody(&b, dx: 16, dy: 0, dz: 0)
                bodies.append(b)
            }

            // Project from eye point (like a flashlight)
            if let projected = Shape.projectWireConical(
                circleShape, onto: box, eye: SIMD3(0, 0, 10)
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    projected, id: "cone-proj", color: SIMD4(1.0, 0.3, 0.3, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: 16, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }

            // Show eye point
            var eye = makeMarker(at: SIMD3(0, 0, 10), radius: 0.2, id: "cone-eye",
                                 color: SIMD4(1.0, 1.0, 0.0, 1.0))
            offsetBody(&eye, dx: 16, dy: 0, dz: 0)
            bodies.append(eye)
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.36: Face division (blue, more patches), conical projection from eye (right)"
        )
    }

    // MARK: - v0.37: Hollow Solid & Wire Analysis

    /// Demonstrates hollowing (thick solid) and wire topology analysis.
    static func hollowAndAnalysis() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Hollow box: remove top face, create shell with wall thickness
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "hollow-orig", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if let body { bodies.append(body) }

            // Try removing face 2 (typically top face) with 0.3 wall thickness
            for faceIdx in 0..<box.contents.faces {
                if let hollowed = box.hollowed(removingFaces: [faceIdx], thickness: 0.3) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        hollowed, id: "hollow-result", color: SIMD4(0.3, 0.7, 1.0, 0.9)
                    )
                    if var body {
                        offsetBody(&body, dx: 8, dy: 0, dz: 0)
                        bodies.append(body)
                    }
                    descriptions.append("Hollowed: face \(faceIdx) removed")
                    break
                }
            }
        }

        // Multi-tool common: intersection of 3 cylinders
        if let c1 = Shape.cylinder(radius: 2, height: 6),
           let c2 = Shape.cylinder(radius: 2, height: 6)?.rotated(axis: SIMD3(1, 0, 0), angle: .pi / 2),
           let c3 = Shape.cylinder(radius: 2, height: 6)?.rotated(axis: SIMD3(0, 1, 0), angle: .pi / 2) {

            if let common = Shape.commonAll([c1, c2, c3]) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    common, id: "common-result", color: SIMD4(0.9, 0.5, 0.3, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 16, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("commonAll: 3 cylinders")
            }
        }

        // Wire analysis demo
        if let wire = Wire.circle(radius: 2) {
            if let analysis = wire.analyze() {
                descriptions.append("Wire: closed=\(analysis.isClosed), edges=\(analysis.edgeCount)")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.37: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.38: Oriented Bounding Box

    /// Shows AABB vs OBB on the same shape — OBB fits tighter on rotated geometry.
    static func orientedBoundingBox() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Build an L-shaped part and rotate it so AABB wastes space but OBB fits tight
        if let arm1 = Shape.box(width: 6, height: 1, depth: 1),
           let arm2 = Shape.box(width: 1, height: 4, depth: 1)?.translated(by: SIMD3(2.5, 2.5, 0)),
           let lShape = arm1.union(with: arm2),
           let rotated = lShape.rotated(axis: SIMD3(0, 0, 1), angle: .pi / 5) {

            // The solid shape
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                rotated, id: "obb-shape", color: SIMD4(0.5, 0.7, 0.9, 1.0)
            )
            if let body { bodies.append(body) }

            // AABB — axis-aligned, wastes space on rotated shapes
            if let bb = body?.boundingBox {
                let lo = bb.min
                let hi = bb.max
                let c = [
                    SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z),
                    SIMD3(lo.x, hi.y, lo.z), SIMD3(hi.x, hi.y, lo.z),
                    SIMD3(lo.x, lo.y, hi.z), SIMD3(hi.x, lo.y, hi.z),
                    SIMD3(lo.x, hi.y, hi.z), SIMD3(hi.x, hi.y, hi.z)
                ]
                let aabbEdges: [[SIMD3<Float>]] = [
                    [c[0], c[1]], [c[1], c[3]], [c[3], c[2]], [c[2], c[0]],
                    [c[4], c[5]], [c[5], c[7]], [c[7], c[6]], [c[6], c[4]],
                    [c[0], c[4]], [c[1], c[5]], [c[2], c[6]], [c[3], c[7]]
                ]
                bodies.append(ViewportBody(id: "obb-aabb", vertexData: [], indices: [],
                                           edges: aabbEdges,
                                           color: SIMD4(1.0, 0.3, 0.3, 1.0)))
            }

            // OBB — oriented, fits tighter
            if let corners = rotated.orientedBoundingBoxCorners(optimal: true) {
                let fc = corners.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
                if fc.count == 8 {
                    let obbEdges: [[SIMD3<Float>]] = [
                        [fc[0], fc[1]], [fc[1], fc[3]], [fc[3], fc[2]], [fc[2], fc[0]],
                        [fc[4], fc[5]], [fc[5], fc[7]], [fc[7], fc[6]], [fc[6], fc[4]],
                        [fc[0], fc[4]], [fc[1], fc[5]], [fc[2], fc[6]], [fc[3], fc[7]]
                    ]
                    bodies.append(ViewportBody(id: "obb-tight", vertexData: [], indices: [],
                                               edges: obbEdges,
                                               color: SIMD4(0.2, 1.0, 0.3, 1.0)))
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Oriented bounding box: red = axis-aligned (loose), green = oriented (tight fit)"
        )
    }

    // MARK: - v0.38: Fuse & Blend

    /// Boolean union + automatic fillet at intersection vs plain union.
    static func fuseAndBlend() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        if let box = Shape.box(width: 4, height: 4, depth: 4),
           let cyl = Shape.cylinder(radius: 1.0, height: 8)?.translated(by: SIMD3(0, -4, 0)) {

            // Left: plain union (sharp edges at intersection)
            if let plain = box.union(with: cyl) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    plain, id: "fb-plain", color: SIMD4(0.6, 0.6, 0.6, 0.9)
                )
                if let body { bodies.append(body) }
            }

            // Right: fuse-and-blend (auto-filleted intersection edges)
            if let blended = box.fusedAndBlended(with: cyl, radius: 0.15) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    blended, id: "fb-blended", color: SIMD4(0.3, 0.7, 1.0, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 9, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }

            // Far right: cut-and-blend (hole with filleted edges)
            if let cut = box.cutAndBlended(with: cyl, radius: 0.15) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    cut, id: "fb-cutblend", color: SIMD4(0.9, 0.5, 0.3, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 18, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Left: plain union (sharp). Center: fuse+blend (filleted). Right: cut+blend (filleted hole)."
        )
    }

    // MARK: - v0.38: Per-Face Variable Offset

    /// Offsets each face of a box by a different amount.
    static func variableOffset() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        if let box = Shape.box(width: 3, height: 3, depth: 3) {
            // Original box (transparent)
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "vo-orig", color: SIMD4(0.6, 0.6, 0.6, 0.3)
            )
            if let orig { bodies.append(orig) }

            // Uniform offset for comparison
            if let uniform = box.offset(by: 0.3) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    uniform, id: "vo-uniform", color: SIMD4(0.3, 0.7, 1.0, 0.6)
                )
                if var body {
                    offsetBody(&body, dx: 7, dy: 0, dz: 0)
                    bodies.append(body)
                }
                // Show original at same position
                let (ref, _) = CADFileLoader.shapeToBodyAndMetadata(
                    box, id: "vo-ref1", color: SIMD4(0.6, 0.6, 0.6, 0.3)
                )
                if var ref {
                    offsetBody(&ref, dx: 7, dy: 0, dz: 0)
                    bodies.append(ref)
                }
            }

            // Per-face variable offset — some faces grow more than others
            if let variable = box.offsetPerFace(
                defaultOffset: 0.1,
                faceOffsets: [1: 0.8, 3: 0.5]
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    variable, id: "vo-variable", color: SIMD4(0.9, 0.5, 0.3, 0.6)
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 0, dz: 0)
                    bodies.append(body)
                }
                // Show original at same position
                let (ref, _) = CADFileLoader.shapeToBodyAndMetadata(
                    box, id: "vo-ref2", color: SIMD4(0.6, 0.6, 0.6, 0.3)
                )
                if var ref {
                    offsetBody(&ref, dx: 14, dy: 0, dz: 0)
                    bodies.append(ref)
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Left: original. Center: uniform offset. Right: per-face variable offset (some faces thicker)."
        )
    }

    // MARK: - Helpers

    private static func uniformParameters(curve: Curve3D, count: Int) -> [Double] {
        let d = curve.domain
        let step = (d.upperBound - d.lowerBound) / Double(count)
        return (0...count).map { d.lowerBound + Double($0) * step }
    }

    private static func wireToBody(
        _ wire: Wire,
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        let edgeCount = wire.orderedEdgeCount
        var polylines: [[SIMD3<Float>]] = []

        for i in 0..<edgeCount {
            if let pts = wire.orderedEdgePoints(at: i, maxPoints: 10000) {
                let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
                if floatPts.count >= 2 {
                    polylines.append(floatPts)
                }
            }
        }

        // Fallback: if orderedEdgePoints didn't work, wrap as Shape for edge extraction
        if polylines.isEmpty, let shape = Shape.fromWire(wire) {
            let count = shape.edgeCount
            for i in 0..<count {
                if let pts = shape.edgePolyline(at: i, deflection: 0.1) {
                    let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
                    if floatPts.count >= 2 {
                        polylines.append(floatPts)
                    }
                }
            }
        }

        return ViewportBody(
            id: id,
            vertexData: [],
            indices: [],
            edges: polylines,
            color: color
        )
    }

    private static func makeMarker(
        at position: SIMD3<Float>,
        radius: Float,
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        var sphere = ViewportBody.sphere(
            id: id, radius: radius, segments: 8, rings: 4, color: color
        )
        let stride = 6
        var verts: [Float] = []
        verts.reserveCapacity(sphere.vertexData.count)
        for i in Swift.stride(from: 0, to: sphere.vertexData.count, by: stride) {
            verts.append(sphere.vertexData[i] + position.x)
            verts.append(sphere.vertexData[i + 1] + position.y)
            verts.append(sphere.vertexData[i + 2] + position.z)
            verts.append(sphere.vertexData[i + 3])
            verts.append(sphere.vertexData[i + 4])
            verts.append(sphere.vertexData[i + 5])
        }
        sphere.vertexData = verts
        return sphere
    }

    private static func offsetBody(_ body: inout ViewportBody, dx: Float, dy: Float, dz: Float) {
        let stride = 6
        var verts: [Float] = []
        verts.reserveCapacity(body.vertexData.count)
        for i in Swift.stride(from: 0, to: body.vertexData.count, by: stride) {
            verts.append(body.vertexData[i] + dx)
            verts.append(body.vertexData[i + 1] + dy)
            verts.append(body.vertexData[i + 2] + dz)
            verts.append(body.vertexData[i + 3])
            verts.append(body.vertexData[i + 4])
            verts.append(body.vertexData[i + 5])
        }
        body.vertexData = verts
        body.edges = body.edges.map { polyline in
            polyline.map { p in SIMD3(p.x + dx, p.y + dy, p.z + dz) }
        }
    }

    private static func hatchToBody(
        _ segments: [HatchSegment],
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        let polylines: [[SIMD3<Float>]] = segments.map { seg in
            [
                SIMD3<Float>(Float(seg.start.x), Float(seg.start.y), 0),
                SIMD3<Float>(Float(seg.end.x), Float(seg.end.y), 0),
            ]
        }
        return ViewportBody(
            id: id,
            vertexData: [],
            indices: [],
            edges: polylines,
            color: color
        )
    }

    private static func boundaryToBody(
        _ boundary: [SIMD2<Double>],
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        var polyline: [SIMD3<Float>] = boundary.map {
            SIMD3<Float>(Float($0.x), Float($0.y), 0)
        }
        // Close the loop
        if let first = polyline.first {
            polyline.append(first)
        }
        return ViewportBody(
            id: id,
            vertexData: [],
            indices: [],
            edges: [polyline],
            color: color
        )
    }

    private static func makeRegularPolygon(
        center: SIMD2<Double>,
        radius: Double,
        sides: Int
    ) -> [SIMD2<Double>] {
        (0..<sides).map { i in
            let angle = Double(i) / Double(sides) * 2 * .pi
            return SIMD2(
                center.x + radius * cos(angle),
                center.y + radius * sin(angle)
            )
        }
    }

    private static func samplePolynomial(
        _ f: (Double) -> Double,
        xRange: ClosedRange<Double>,
        yOffset: Double,
        yScale: Double = 1.0
    ) -> [SIMD3<Float>] {
        let steps = 200
        let dx = (xRange.upperBound - xRange.lowerBound) / Double(steps)
        return (0...steps).map { i in
            let x = xRange.lowerBound + Double(i) * dx
            let y = yOffset + f(x) * yScale
            return SIMD3<Float>(Float(x), Float(y), 0)
        }
    }

    private static func polylineToBody(
        _ points: [SIMD3<Float>],
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        ViewportBody(
            id: id,
            vertexData: [],
            indices: [],
            edges: [points],
            color: color
        )
    }
}
