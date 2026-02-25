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
            if let pts = wire.orderedEdgePoints(at: i) {
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
