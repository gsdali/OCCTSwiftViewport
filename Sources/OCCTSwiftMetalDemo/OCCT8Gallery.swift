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

    /// Demonstrates NURBS conversion and fast sewing.
    static func shapeOperations() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Original cylinder
        if let cyl = Shape.cylinder(radius: 1.5, height: 4.0) {
            let origContents = cyl.contents
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "op-original", color: SIMD4(0.6, 0.6, 0.6, 0.5)
            )
            if let body { bodies.append(body) }

            // NURBS-converted version — offset right
            if let nurbs = cyl.convertedToNURBS() {
                let nurbsContents = nurbs.contents
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    nurbs, id: "op-nurbs", color: SIMD4(0.3, 0.7, 1.0, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: 5, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("NURBS: \(origContents.faces)F→\(nurbsContents.faces)F")
            }
        }

        // Fast sewing: explode a box into loose shells, then sew back together
        if let box = Shape.box(width: 3, height: 2, depth: 2) {
            let origContents = box.contents
            // Show the original box
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "op-presew", color: SIMD4(0.6, 0.6, 0.6, 0.5)
            )
            if var orig {
                offsetBody(&orig, dx: -5, dy: 0, dz: 0)
                bodies.append(orig)
            }

            if let sewn = box.fastSewn() {
                let sewnContents = sewn.contents
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    sewn, id: "op-fastsewn", color: SIMD4(0.9, 0.6, 0.3, 1.0)
                )
                if var body {
                    offsetBody(&body, dx: -5, dy: 5, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("Sew: \(origContents.shells)sh→\(sewnContents.shells)sh")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.29 Shape ops: " + descriptions.joined(separator: " | ")
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
        var descriptions: [String] = []

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
                descriptions.append("makeVolume: \(c.solids)S \(c.faces)F")
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
                let c = connected.contents
                descriptions.append("makeConnected: \(c.solids)S \(c.faces)F")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.30: " + descriptions.joined(separator: " | ")
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
        var descriptions: [String] = []

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
                descriptions.append("Cyl split90: \(origContents.faces)F→\(splitContents.faces)F")
            }
        }

        // Sphere — split by 90° creates octant patches
        if let sph = Shape.sphere(radius: 2) {
            let origContents = sph.contents
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
                let splitContents = split.contents
                descriptions.append("Sph split90: \(origContents.faces)F→\(splitContents.faces)F")
            }
        }

        // Drop small edges demo: create a shape with tiny edges then clean
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            // Fillet with a very small radius to create tiny edges
            if let filleted = box.filleted(radius: 0.01) {
                let filletedContents = filleted.contents
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    filleted, id: "repair-tiny", color: SIMD4(0.6, 0.6, 0.6, 0.5)
                )
                if var body {
                    offsetBody(&body, dx: 0, dy: 14, dz: 0)
                    bodies.append(body)
                }

                if let cleaned = filleted.droppingSmallEdges(tolerance: 0.05) {
                    let cleanedContents = cleaned.contents
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        cleaned, id: "repair-cleaned", color: SIMD4(0.3, 0.9, 0.4, 0.9)
                    )
                    if var body {
                        offsetBody(&body, dx: 7, dy: 14, dz: 0)
                        bodies.append(body)
                    }
                    descriptions.append("DropSmall: \(filletedContents.edges)E→\(cleanedContents.edges)E")
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.34 Repair: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.34: Multi-Fuse

    /// Demonstrates fuseAll vs sequential union for multiple shapes.
    static func multiFuse() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Create 4 overlapping cylinders in a cross pattern
        let shapes: [Shape] = {
            var result: [Shape] = []
            if let c1 = Shape.cylinder(radius: 1, height: 6) {
                result.append(c1)
            }
            if let c2 = Shape.cylinder(radius: 1, height: 6)?.rotated(axis: SIMD3(1, 0, 0), angle: .pi / 2) {
                result.append(c2)
            }
            if let c3 = Shape.cylinder(radius: 1, height: 6)?.rotated(axis: SIMD3(0, 1, 0), angle: .pi / 2) {
                result.append(c3)
            }
            if let c4 = Shape.cylinder(radius: 0.8, height: 6)?.rotated(axis: SIMD3(1, 1, 0), angle: .pi / 4) {
                result.append(c4)
            }
            return result
        }()

        // Show individual cylinders semi-transparent
        let colors: [SIMD4<Float>] = [
            SIMD4(0.3, 0.6, 1.0, 0.2), SIMD4(0.9, 0.5, 0.3, 0.2),
            SIMD4(0.3, 0.9, 0.4, 0.2), SIMD4(0.8, 0.4, 0.8, 0.2)
        ]
        for (i, shape) in shapes.enumerated() {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                shape, id: "fuse-orig-\(i)", color: colors[i],
                deflection: 0.02
            )
            if let body { bodies.append(body) }
        }

        // fuseAll — simultaneous multi-tool boolean
        if let fused = Shape.fuseAll(shapes) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                fused, id: "fuse-all", color: SIMD4(0.3, 0.7, 1.0, 0.9),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 10, dy: 0, dz: 0)
                bodies.append(body)
            }
            let c = fused.contents
            descriptions.append("fuseAll: \(c.faces)F \(c.edges)E")
        }

        // Sequential union for comparison
        var seqResult: Shape? = shapes.first
        for shape in shapes.dropFirst() {
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
            let c = seq.contents
            descriptions.append("sequential: \(c.faces)F \(c.edges)E")
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.34 Multi-fuse: " + descriptions.joined(separator: " vs ")
        )
    }

    // MARK: - v0.34: Split Face by Wire

    /// Demonstrates imprinting a wire onto a face to split it.
    static func splitFaceByWire() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var desc = "v0.34 Split face: original (gray)"

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
                // Top face index varies by OCCT internals; try all faces
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
                            desc += ", split face \(faceIdx): \(origContents.faces)F→\(splitContents.faces)F (blue)"
                            break
                        }
                    }
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: desc
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
        var descriptions: [String] = []

        // Face division: split cylinder faces into patches
        if let cyl = Shape.cylinder(radius: 2, height: 4) {
            let origC = cyl.contents
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

                let divC = divided.contents
                descriptions.append("Divide: \(origC.faces)F→\(divC.faces)F")
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
            description: "v0.36: " + descriptions.joined(separator: " | ") + ". Conical projection (right)."
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

    // MARK: - v0.39: Free Bounds, Pipe Feature, Semi-Infinite Extrusion

    /// Demonstrates free boundary analysis, pipe feature, and semi-infinite extrusion.
    static func freeBoundsAndFeatures() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Free bounds: open shell (box missing one face) should show free edges
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            // Show the original solid box
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "fb-solid", color: SIMD4(0.6, 0.6, 0.6, 0.4)
            )
            if let orig { bodies.append(orig) }

            // Analyze free bounds on the solid (should have none)
            if let fb = box.freeBounds() {
                descriptions.append("Solid: \(fb.closedCount) closed, \(fb.openCount) open free bounds")
            } else {
                descriptions.append("Solid: no free bounds (watertight)")
            }

            // Hollow the box to create an open shell, then check free bounds
            for faceIdx in 0..<box.contents.faces {
                if let hollowed = box.hollowed(removingFaces: [faceIdx], thickness: 0.3) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        hollowed, id: "fb-open", color: SIMD4(0.3, 0.7, 1.0, 0.8)
                    )
                    if var body {
                        offsetBody(&body, dx: 8, dy: 0, dz: 0)
                        bodies.append(body)
                    }

                    if let fb = hollowed.freeBounds() {
                        descriptions.append("Hollow: \(fb.closedCount) closed, \(fb.openCount) open")
                        // Show the free boundary wires
                        let (wireBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                            fb.wires, id: "fb-wires", color: SIMD4(1.0, 0.2, 0.2, 1.0),
                            deflection: 0.02
                        )
                        if var wireBody {
                            offsetBody(&wireBody, dx: 8, dy: 0, dz: 0)
                            bodies.append(wireBody)
                        }
                    }
                    break
                }
            }
        }

        // Semi-infinite extrusion
        if let circle = Wire.circle(radius: 1),
           let face = Shape.face(from: circle) {
            if let semiInf = face.extrudedSemiInfinite(direction: SIMD3(0, 0, 1)) {
                // The semi-infinite shape is huge; section it with a box for display
                if let clipBox = Shape.box(width: 6, height: 6, depth: 8),
                   let clipped = clipBox.intersection(with: semiInf) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        clipped, id: "fb-semiinf", color: SIMD4(0.9, 0.5, 0.3, 0.8),
                        deflection: 0.02
                    )
                    if var body {
                        offsetBody(&body, dx: 16, dy: 0, dz: 0)
                        bodies.append(body)
                    }
                    descriptions.append("Semi-inf extrusion (clipped)")
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.39: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.40: Inertia Properties & Extended Distance

    /// Demonstrates volume/surface inertia and multi-solution distance queries.
    static func inertiaAndDistance() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Inertia properties: box vs cylinder — compare center of mass and principal axes
        if let box = Shape.box(width: 6, height: 2, depth: 3) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "inertia-box", color: SIMD4(0.3, 0.6, 1.0, 0.8)
            )
            if let body { bodies.append(body) }

            if let props = box.inertiaProperties() {
                let com = props.centerOfMass
                bodies.append(makeMarker(
                    at: SIMD3<Float>(Float(com.x), Float(com.y), Float(com.z)),
                    radius: 0.2, id: "inertia-box-com",
                    color: SIMD4(1.0, 0.2, 0.2, 1.0)
                ))

                // Show principal axes as lines from center of mass
                let axisLen: Double = 2.0
                let axisColors: [SIMD4<Float>] = [
                    SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1), SIMD4(0, 0, 1, 1)
                ]
                let axes = [props.principalAxes.0, props.principalAxes.1, props.principalAxes.2]
                for (i, axis) in axes.enumerated() {
                    let start = SIMD3<Float>(Float(com.x), Float(com.y), Float(com.z))
                    let end = SIMD3<Float>(
                        Float(com.x + axis.x * axisLen),
                        Float(com.y + axis.y * axisLen),
                        Float(com.z + axis.z * axisLen)
                    )
                    bodies.append(ViewportBody(id: "inertia-box-axis-\(i)", vertexData: [], indices: [],
                                               edges: [[start, end]], color: axisColors[i]))
                }
                descriptions.append("Box: vol=\(String(format: "%.1f", props.mass))")
            }
        }

        if let cyl = Shape.cylinder(radius: 1.5, height: 4) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "inertia-cyl", color: SIMD4(0.3, 0.9, 0.4, 0.8),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 10, dy: 0, dz: 0)
                bodies.append(body)
            }

            if let props = cyl.inertiaProperties() {
                let com = props.centerOfMass
                var marker = makeMarker(
                    at: SIMD3<Float>(Float(com.x), Float(com.y), Float(com.z)),
                    radius: 0.2, id: "inertia-cyl-com",
                    color: SIMD4(1.0, 0.2, 0.2, 1.0)
                )
                offsetBody(&marker, dx: 10, dy: 0, dz: 0)
                bodies.append(marker)
                descriptions.append("Cyl: vol=\(String(format: "%.1f", props.mass))")
            }
        }

        // Extended distance: all closest point pairs between two shapes
        if let box = Shape.box(width: 2, height: 2, depth: 2),
           let sph = Shape.sphere(radius: 1)?.translated(by: SIMD3(4, 0, 0)) {

            let (b1, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "dist-box", color: SIMD4(0.5, 0.7, 0.9, 0.6)
            )
            if var b1 {
                offsetBody(&b1, dx: 0, dy: 8, dz: 0)
                bodies.append(b1)
            }
            let (b2, _) = CADFileLoader.shapeToBodyAndMetadata(
                sph, id: "dist-sph", color: SIMD4(0.9, 0.6, 0.4, 0.6),
                deflection: 0.02
            )
            if var b2 {
                offsetBody(&b2, dx: 0, dy: 8, dz: 0)
                bodies.append(b2)
            }

            if let solutions = box.allDistanceSolutions(to: sph, maxSolutions: 8) {
                for (i, sol) in solutions.enumerated() {
                    let p1 = SIMD3<Float>(Float(sol.point1.x), Float(sol.point1.y) + 8, Float(sol.point1.z))
                    let p2 = SIMD3<Float>(Float(sol.point2.x), Float(sol.point2.y) + 8, Float(sol.point2.z))
                    bodies.append(makeMarker(at: p1, radius: 0.1, id: "dist-p1-\(i)",
                                             color: SIMD4(1.0, 0.2, 0.2, 1.0)))
                    bodies.append(makeMarker(at: p2, radius: 0.1, id: "dist-p2-\(i)",
                                             color: SIMD4(0.2, 1.0, 0.2, 1.0)))
                    bodies.append(ViewportBody(id: "dist-line-\(i)", vertexData: [], indices: [],
                                               edges: [[p1, p2]], color: SIMD4(1.0, 1.0, 0.0, 1.0)))
                }
                descriptions.append("\(solutions.count) distance solutions")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.40: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.41: Shape Surgery & Plane Detection

    /// Demonstrates plane detection, geometry conversion, closed edge splitting,
    /// and face restriction.
    static func surgeryAndDetection() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Face restriction: cut a face using a wire boundary
        if let cyl = Shape.cylinder(radius: 2, height: 5) {
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "restrict-orig", color: SIMD4(0.6, 0.6, 0.6, 0.4),
                deflection: 0.02
            )
            if let orig { bodies.append(orig) }

            // Create a restricting wire (a circle on the XY plane)
            if let clipWire = Wire.circle(radius: 1.5) {
                if let restricted = cyl.faceRestricted(by: [clipWire]) {
                    for (i, face) in restricted.enumerated() {
                        let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                            face, id: "restrict-\(i)", color: SIMD4(0.3, 0.7, 1.0, 0.9),
                            deflection: 0.02
                        )
                        if var body {
                            offsetBody(&body, dx: 6, dy: 0, dz: 0)
                            bodies.append(body)
                        }
                    }
                    descriptions.append("Face restrict: \(restricted.count) result faces")
                }
            }
        }

        // Plane detection: check if various wires are planar
        if let flatWire = Wire.path([
            SIMD3(0, 0, 0), SIMD3(3, 0, 0), SIMD3(3, 3, 0), SIMD3(0, 3, 0)
        ], closed: true),
           let flatShape = Shape.fromWire(flatWire) {

            // Show the wire
            var flatBody = wireToBody(flatWire, id: "plane-flat",
                                      color: SIMD4(0.3, 0.9, 0.4, 1.0))
            offsetBody(&flatBody, dx: 14, dy: 0, dz: 0)
            bodies.append(flatBody)

            if let plane = flatShape.findPlane() {
                let n = plane.normal
                let o = plane.origin
                descriptions.append("Planar: n=(\(String(format: "%.0f,%.0f,%.0f", n.x, n.y, n.z)))")

                // Show the detected plane normal as a line from the wire's center
                let start = SIMD3<Float>(Float(o.x) + 14, Float(o.y), Float(o.z))
                let end = SIMD3<Float>(Float(o.x + n.x * 2) + 14, Float(o.y + n.y * 2), Float(o.z + n.z * 2))
                bodies.append(ViewportBody(id: "plane-normal", vertexData: [], indices: [],
                                           edges: [[start, end]], color: SIMD4(1.0, 0.3, 0.3, 1.0)))
            }
        }

        // Geometry conversion: cylinder surfaces to BSpline and to Revolution
        if let cyl = Shape.cylinder(radius: 2, height: 4) {
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "conv-orig", color: SIMD4(0.6, 0.6, 0.6, 0.5),
                deflection: 0.02
            )
            if var orig {
                offsetBody(&orig, dx: 0, dy: 10, dz: 0)
                bodies.append(orig)
            }

            if let bspline = cyl.withSurfacesAsBSpline() {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    bspline, id: "conv-bspline", color: SIMD4(0.9, 0.5, 0.3, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 6, dy: 10, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("Surfaces→BSpline")
            }

            if let rev = cyl.withSurfacesAsRevolution() {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    rev, id: "conv-revolution", color: SIMD4(0.3, 0.9, 0.7, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 12, dy: 10, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("Surfaces→Revolution")
            }
        }

        // SubShape API: extract individual faces, count sub-shapes, remove a face
        if let box = Shape.box(width: 3, height: 3, depth: 3) {
            // Fillet the box first for a more interesting shape
            let target = box.filleted(radius: 0.4) ?? box

            let faceCount = target.subShapeCount(ofType: .face)
            let edgeCount = target.subShapeCount(ofType: .edge)
            let vertexCount = target.subShapeCount(ofType: .vertex)
            descriptions.append("SubShape: \(faceCount)F \(edgeCount)E \(vertexCount)V")

            // Show the original filleted box (semi-transparent)
            let (origBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                target, id: "subshape-orig", color: SIMD4(0.6, 0.6, 0.6, 0.3),
                deflection: 0.02
            )
            if var origBody {
                offsetBody(&origBody, dx: 0, dy: 20, dz: 0)
                bodies.append(origBody)
            }

            // Extract face 0 and remove it
            if let face0 = target.subShape(type: .face, index: 0) {
                let (faceBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                    face0, id: "subshape-face0", color: SIMD4(1.0, 0.3, 0.3, 0.9),
                    deflection: 0.02
                )
                if var faceBody {
                    offsetBody(&faceBody, dx: 0, dy: 20, dz: 0)
                    bodies.append(faceBody)
                }

                // Remove that face
                if let removed = target.removingSubShapes([face0]) {
                    let removedFaceCount = removed.subShapeCount(ofType: .face)
                    let (removedBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                        removed, id: "subshape-removed", color: SIMD4(0.3, 0.8, 0.5, 0.9),
                        deflection: 0.02
                    )
                    if var removedBody {
                        offsetBody(&removedBody, dx: 7, dy: 20, dz: 0)
                        bodies.append(removedBody)
                    }
                    descriptions.append("Removed 1 face: \(faceCount)→\(removedFaceCount)F")
                }
            }

            // Visualize all faces individually with per-face colors
            let allFaces = target.subShapes(ofType: .face)
            let faceColors: [SIMD4<Float>] = [
                SIMD4(0.9, 0.3, 0.3, 0.8), SIMD4(0.3, 0.9, 0.3, 0.8),
                SIMD4(0.3, 0.3, 0.9, 0.8), SIMD4(0.9, 0.9, 0.3, 0.8),
                SIMD4(0.9, 0.3, 0.9, 0.8), SIMD4(0.3, 0.9, 0.9, 0.8),
                SIMD4(0.9, 0.6, 0.3, 0.8), SIMD4(0.6, 0.3, 0.9, 0.8),
            ]
            for (i, face) in allFaces.enumerated() {
                let color = faceColors[i % faceColors.count]
                let (faceBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                    face, id: "subshape-all-\(i)", color: color,
                    deflection: 0.02
                )
                if var faceBody {
                    offsetBody(&faceBody, dx: 14, dy: 20, dz: 0)
                    bodies.append(faceBody)
                }
            }
            descriptions.append("All \(allFaces.count) faces colored")
        }

        // Closed edge splitting
        if let cyl = Shape.cylinder(radius: 1.5, height: 3) {
            let origContents = cyl.contents
            if let split = cyl.dividedClosedEdges() {
                let splitContents = split.contents
                descriptions.append("Split closed edges: \(origContents.edges)E→\(splitContents.edges)E")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.41: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.42: Solid Construction, 2D Fillets, Polygon3D, Point Cloud

    /// Demonstrates solidFromShells, polygon3D, fillet2D, chamfer2D, and analyzePointCloud.
    static func solidAnd2DFillets() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- solidFromShells: hollow solid with cavity ---
        if let outer = Shape.box(width: 10, height: 10, depth: 10),
           let inner = Shape.box(width: 6, height: 6, depth: 6)?
            .translated(by: SIMD3(2, 2, 2)) {
            // Shell the outer and inner boxes
            if let solid = Shape.solidFromShells([outer, inner]) {
                // Section it to reveal the cavity
                if let cutter = Shape.box(width: 12, height: 12, depth: 12)?
                    .translated(by: SIMD3(-1, 5, -1)),
                   let sectioned = solid.subtracting(cutter) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        sectioned, id: "solid-hollow", color: SIMD4(0.4, 0.6, 0.9, 0.9),
                        deflection: 0.02
                    )
                    if let body { bodies.append(body) }
                    descriptions.append("solidFromShells: hollow box")
                } else {
                    // Show the solid without section cut
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        solid, id: "solid-hollow", color: SIMD4(0.4, 0.6, 0.9, 0.7),
                        deflection: 0.02
                    )
                    if let body { bodies.append(body) }
                    descriptions.append("solidFromShells: hollow box (no section)")
                }
            }
        }

        // --- polygon3D: 3D star wire extruded into a prism ---
        let starPoints: [SIMD3<Double>] = (0..<10).map { i in
            let angle = Double(i) / 10.0 * 2.0 * .pi
            let r: Double = i % 2 == 0 ? 4.0 : 2.0
            return SIMD3(r * cos(angle), r * sin(angle), 0)
        }
        if let starWire = Wire.polygon3D(starPoints, closed: true) {
            // Show the wire
            var wireBody = wireToBody(starWire, id: "poly3d-wire",
                                       color: SIMD4(1.0, 0.8, 0.2, 1.0))
            offsetBody(&wireBody, dx: 16, dy: 0, dz: 0)
            bodies.append(wireBody)

            // Extrude into a prism
            if let prism = Shape.extrude(profile: starWire, direction: SIMD3(0, 0, 1), length: 5) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    prism, id: "poly3d-prism", color: SIMD4(0.9, 0.7, 0.2, 0.85),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 26, dy: 0, dz: 0)
                    bodies.append(body)
                }
            }
            descriptions.append("polygon3D: 10-pt star → prism")
        }

        // --- fillet2D: rounded corners on a rectangle ---
        if let rectWire = Wire.rectangle(width: 10, height: 8),
           let rectFace = Shape.face(from: rectWire) {
            // Original rectangle
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                rectFace, id: "fillet2d-orig", color: SIMD4(0.6, 0.6, 0.6, 0.5),
                deflection: 0.02
            )
            if var orig {
                offsetBody(&orig, dx: 0, dy: 16, dz: 0)
                bodies.append(orig)
            }

            // Fillet all 4 corners with different radii
            if let filleted = rectFace.fillet2D(
                vertexIndices: [0, 1, 2, 3],
                radii: [1.0, 2.0, 1.0, 2.0]
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    filleted, id: "fillet2d-result", color: SIMD4(0.3, 0.8, 0.4, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 16, dz: 0)
                    bodies.append(body)
                }
                let edgeCount = filleted.subShapeCount(ofType: .edge)
                descriptions.append("fillet2D: 4→\(edgeCount) edges")
            }
        }

        // --- chamfer2D: angled cuts on a square ---
        if let sqWire = Wire.rectangle(width: 8, height: 8),
           let sqFace = Shape.face(from: sqWire) {
            // Chamfer one corner
            if let chamfered = sqFace.chamfer2D(
                edgePairs: [(0, 1)],
                distances: [2.0]
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    chamfered, id: "chamfer2d-result", color: SIMD4(0.9, 0.5, 0.3, 0.9),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 28, dy: 16, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("chamfer2D: 1 corner cut")
            }
        }

        // --- analyzePointCloud: 4 classification scenarios ---
        let classifications: [(String, [SIMD3<Double>], SIMD4<Float>)] = [
            ("point", [SIMD3(0, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 0, 0)],
             SIMD4(1, 0.3, 0.3, 1)),
            ("linear", [SIMD3(0, 0, 0), SIMD3(5, 0, 0), SIMD3(10, 0, 0)],
             SIMD4(0.3, 1, 0.3, 1)),
            ("planar", [SIMD3(0, 0, 0), SIMD3(5, 0, 0), SIMD3(5, 5, 0), SIMD3(0, 5, 0)],
             SIMD4(0.3, 0.3, 1, 1)),
            ("space", [SIMD3(0, 0, 0), SIMD3(5, 0, 0), SIMD3(0, 5, 0), SIMD3(0, 0, 5)],
             SIMD4(0.9, 0.9, 0.3, 1)),
        ]
        for (ci, (label, pts, color)) in classifications.enumerated() {
            let dx = Float(ci) * 8
            // Show points as small markers
            for (pi, p) in pts.enumerated() {
                var marker = makeMarker(
                    at: SIMD3(Float(p.x), Float(p.y), Float(p.z)),
                    radius: 0.3, id: "ptcloud-\(label)-\(pi)", color: color
                )
                offsetBody(&marker, dx: dx, dy: 28, dz: 0)
                bodies.append(marker)
            }

            if let result = Shape.analyzePointCloud(pts) {
                switch result {
                case .point:
                    descriptions.append("\(label):coincident")
                case .linear(let origin, let dir):
                    // Draw the fit line
                    let o = SIMD3<Float>(Float(origin.x), Float(origin.y), Float(origin.z))
                    let d = SIMD3<Float>(Float(dir.x), Float(dir.y), Float(dir.z))
                    let start = o - d * 2
                    let end = o + d * 12
                    var lineBody = ViewportBody(
                        id: "ptcloud-\(label)-line", vertexData: [], indices: [],
                        edges: [[start, end]], color: color
                    )
                    offsetBody(&lineBody, dx: dx, dy: 28, dz: 0)
                    bodies.append(lineBody)
                    descriptions.append("\(label):line")
                case .planar(let origin, let normal):
                    // Draw a normal vector
                    let o = SIMD3<Float>(Float(origin.x), Float(origin.y), Float(origin.z))
                    let n = SIMD3<Float>(Float(normal.x), Float(normal.y), Float(normal.z))
                    var normalBody = ViewportBody(
                        id: "ptcloud-\(label)-normal", vertexData: [], indices: [],
                        edges: [[o, o + n * 3]], color: SIMD4(1, 0.5, 0.5, 1)
                    )
                    offsetBody(&normalBody, dx: dx, dy: 28, dz: 0)
                    bodies.append(normalBody)
                    descriptions.append("\(label):plane")
                case .space:
                    descriptions.append("\(label):3D")
                }
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.42: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.43: BSpline Fill, Face Subdivision, Small Face Detection

    /// Demonstrates bsplineFill (2-curve and 4-curve), dividedByArea, dividedByParts,
    /// checkSmallFaces, and purgedLocations.
    static func bsplineFillAndSubdivision() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- BSpline fill from 2 curves (3 fill styles side by side) ---
        let c1 = Curve3D.interpolate(points: [
            SIMD3(0, 0, 0), SIMD3(3, 0, 2), SIMD3(6, 0, 3), SIMD3(10, 0, 0)
        ])
        let c2 = Curve3D.interpolate(points: [
            SIMD3(0, 8, 0), SIMD3(3, 8, -1), SIMD3(6, 8, 2), SIMD3(10, 8, 0)
        ])

        if let c1, let c2 {
            let styles: [(Surface.FillStyle, String, SIMD4<Float>)] = [
                (.stretch, "stretch", SIMD4(0.3, 0.7, 0.9, 0.85)),
                (.coons, "coons", SIMD4(0.3, 0.9, 0.5, 0.85)),
                (.curved, "curved", SIMD4(0.9, 0.6, 0.3, 0.85)),
            ]
            for (si, (style, name, color)) in styles.enumerated() {
                let dx = Float(si) * 14
                if let surface = Surface.bsplineFill(curve1: c1, curve2: c2, style: style) {
                    let dom = surface.domain
                    if let face = Shape.face(from: surface,
                                              uRange: dom.uMin...dom.uMax,
                                              vRange: dom.vMin...dom.vMax) {
                        let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                            face, id: "bsfill2-\(name)", color: color,
                            deflection: 0.02
                        )
                        if var body {
                            offsetBody(&body, dx: dx, dy: 0, dz: 0)
                            bodies.append(body)
                        }
                    }
                }
                // Show boundary curves as sampled polylines
                let params1 = uniformParameters(curve: c1, count: 40)
                let pts1 = c1.evaluateGrid(params1).map {
                    SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
                }
                var w1 = polylineToBody(pts1, id: "bsfill2-c1-\(name)",
                                        color: SIMD4(1, 1, 1, 1))
                offsetBody(&w1, dx: dx, dy: 0, dz: 0)
                bodies.append(w1)
                let params2 = uniformParameters(curve: c2, count: 40)
                let pts2 = c2.evaluateGrid(params2).map {
                    SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
                }
                var w2 = polylineToBody(pts2, id: "bsfill2-c2-\(name)",
                                        color: SIMD4(1, 1, 1, 1))
                offsetBody(&w2, dx: dx, dy: 0, dz: 0)
                bodies.append(w2)
            }
            descriptions.append("2-curve fill: stretch/coons/curved")
        }

        // --- BSpline fill from 4 curves (Coons patch) ---
        let bottom = Curve3D.interpolate(points: [
            SIMD3(0, 0, 0), SIMD3(4, 0, 2), SIMD3(8, 0, 0)
        ])
        let right = Curve3D.interpolate(points: [
            SIMD3(8, 0, 0), SIMD3(8, 4, 3), SIMD3(8, 8, 0)
        ])
        let top = Curve3D.interpolate(points: [
            SIMD3(8, 8, 0), SIMD3(4, 8, -1), SIMD3(0, 8, 0)
        ])
        let left = Curve3D.interpolate(points: [
            SIMD3(0, 8, 0), SIMD3(0, 4, 1), SIMD3(0, 0, 0)
        ])

        if let b = bottom, let r = right, let t = top, let l = left {
            if let surface = Surface.bsplineFill(curves: (b, r, t, l), style: .coons) {
                let dom = surface.domain
                if let face = Shape.face(from: surface,
                                          uRange: dom.uMin...dom.uMax,
                                          vRange: dom.vMin...dom.vMax) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        face, id: "bsfill4-coons", color: SIMD4(0.8, 0.4, 0.8, 0.85),
                        deflection: 0.02
                    )
                    if var body {
                        offsetBody(&body, dx: 0, dy: 14, dz: 0)
                        bodies.append(body)
                    }
                }
            }
            // Show boundary curves as sampled polylines
            for (curve, label) in [(b, "b"), (r, "r"), (t, "t"), (l, "l")] {
                let params = uniformParameters(curve: curve, count: 40)
                let pts = curve.evaluateGrid(params).map {
                    SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
                }
                var wb = polylineToBody(pts, id: "bsfill4-\(label)",
                                        color: SIMD4(1, 1, 0.3, 1))
                offsetBody(&wb, dx: 0, dy: 14, dz: 0)
                bodies.append(wb)
            }
            descriptions.append("4-curve Coons patch")
        }

        // --- dividedByArea: box faces split by area threshold ---
        if let box = Shape.box(width: 8, height: 8, depth: 8) {
            let origFaceCount = box.subShapeCount(ofType: .face)

            // Show original with per-face colors
            let origFaces = box.subShapes(ofType: .face)
            let faceColors: [SIMD4<Float>] = [
                SIMD4(0.9, 0.4, 0.4, 0.7), SIMD4(0.4, 0.9, 0.4, 0.7),
                SIMD4(0.4, 0.4, 0.9, 0.7), SIMD4(0.9, 0.9, 0.4, 0.7),
                SIMD4(0.9, 0.4, 0.9, 0.7), SIMD4(0.4, 0.9, 0.9, 0.7),
            ]
            for (i, face) in origFaces.enumerated() {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    face, id: "divarea-orig-\(i)", color: faceColors[i % faceColors.count],
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 16, dy: 14, dz: 0)
                    bodies.append(body)
                }
            }

            // Divide by area (each face is 64 sq units, max 20 should split each)
            if let divided = box.dividedByArea(maxArea: 20) {
                let newFaceCount = divided.subShapeCount(ofType: .face)
                let divFaces = divided.subShapes(ofType: .face)
                let moreColors: [SIMD4<Float>] = [
                    SIMD4(0.9, 0.3, 0.3, 0.8), SIMD4(0.3, 0.9, 0.3, 0.8),
                    SIMD4(0.3, 0.3, 0.9, 0.8), SIMD4(0.9, 0.9, 0.3, 0.8),
                    SIMD4(0.9, 0.3, 0.9, 0.8), SIMD4(0.3, 0.9, 0.9, 0.8),
                    SIMD4(0.9, 0.6, 0.3, 0.8), SIMD4(0.6, 0.3, 0.9, 0.8),
                ]
                for (i, face) in divFaces.enumerated() {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        face, id: "divarea-result-\(i)", color: moreColors[i % moreColors.count],
                        deflection: 0.02
                    )
                    if var body {
                        offsetBody(&body, dx: 28, dy: 14, dz: 0)
                        bodies.append(body)
                    }
                }
                descriptions.append("dividedByArea: \(origFaceCount)→\(newFaceCount)F")
            }
        }

        // --- dividedByParts: cylinder faces split into target parts ---
        if let cyl = Shape.cylinder(radius: 4, height: 6) {
            let origFaceCount = cyl.subShapeCount(ofType: .face)
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "divparts-orig", color: SIMD4(0.6, 0.6, 0.6, 0.5),
                deflection: 0.02
            )
            if var orig {
                offsetBody(&orig, dx: 0, dy: 28, dz: 0)
                bodies.append(orig)
            }

            if let divided = cyl.dividedByParts(4) {
                let newFaceCount = divided.subShapeCount(ofType: .face)
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    divided, id: "divparts-result", color: SIMD4(0.5, 0.8, 0.6, 0.85),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 28, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("dividedByParts(4): \(origFaceCount)→\(newFaceCount)F")
            }
        }

        // --- checkSmallFaces: create a shape with degenerate faces and detect them ---
        if let sphere = Shape.sphere(radius: 3) {
            let issues = sphere.checkSmallFaces()
            if issues.isEmpty {
                descriptions.append("checkSmallFaces(sphere): clean")
            } else {
                descriptions.append("checkSmallFaces(sphere): \(issues.count) issues")
                // Highlight spot face locations
                for (i, info) in issues.enumerated() {
                    if let loc = info.spotLocation {
                        var marker = makeMarker(
                            at: SIMD3(Float(loc.x), Float(loc.y), Float(loc.z)),
                            radius: 0.4, id: "smallface-\(i)",
                            color: SIMD4(1, 0, 0, 1)
                        )
                        offsetBody(&marker, dx: 28, dy: 28, dz: 0)
                        bodies.append(marker)
                    }
                }
            }

            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sphere, id: "smallface-sphere", color: SIMD4(0.7, 0.7, 0.8, 0.6),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 28, dy: 28, dz: 0)
                bodies.append(body)
            }
        }

        // --- purgedLocations: mirror creates negative scale, purge cleans it ---
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            if let mirrored = box.mirrored(planeNormal: SIMD3(1, 0, 0)) {
                let hadPurge = mirrored.purgedLocations != nil
                descriptions.append("purgedLocations: \(hadPurge ? "cleaned" : "already clean")")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.42-43: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.44: Surface Extrema, Ellipse Arcs, Edge Analysis, Bezier Convert

    /// Demonstrates surface extrema, ellipse arcs, dihedral angles, Bezier conversion,
    /// and curve-on-surface validation.
    static func extremaAndArcs() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Surface extrema: min distance between a sphere and a plane ---
        if let sphereSurf = Surface.sphere(center: SIMD3(0, 0, 5), radius: 3),
           let planeSurf = Surface.plane(origin: .zero, normal: SIMD3(0, 0, 1)) {
            // Show the sphere shape
            if let sphere = Shape.sphere(radius: 3)?
                .translated(by: SIMD3(0, 0, 5)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    sphere, id: "extrema-sphere", color: SIMD4(0.4, 0.6, 0.9, 0.6),
                    deflection: 0.02
                )
                if let body { bodies.append(body) }
            }
            // Show a ground plane as a thin box
            if let ground = Shape.box(width: 12, height: 12, depth: 0.1)?
                .translated(by: SIMD3(-6, -6, -0.05)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    ground, id: "extrema-plane", color: SIMD4(0.5, 0.7, 0.5, 0.5),
                    deflection: 0.05
                )
                if let body { bodies.append(body) }
            }
            // Compute extrema
            if let result = sphereSurf.extrema(to: planeSurf) {
                let p1 = SIMD3<Float>(Float(result.point1.x), Float(result.point1.y), Float(result.point1.z))
                let p2 = SIMD3<Float>(Float(result.point2.x), Float(result.point2.y), Float(result.point2.z))
                // Distance line between closest points
                bodies.append(ViewportBody(
                    id: "extrema-line", vertexData: [], indices: [],
                    edges: [[p1, p2]], color: SIMD4(1, 0.3, 0.3, 1)
                ))
                // Markers at closest points
                bodies.append(makeMarker(at: p1, radius: 0.2, id: "extrema-p1",
                                          color: SIMD4(1, 0.3, 0.3, 1)))
                bodies.append(makeMarker(at: p2, radius: 0.2, id: "extrema-p2",
                                          color: SIMD4(1, 0.3, 0.3, 1)))
                descriptions.append(String(format: "Extrema: d=%.2f", result.distance))
            }
        }

        // --- Ellipse arcs: quarter, half, and 3/4 arcs in different planes ---
        let arcDefs: [(String, Double, Double, SIMD3<Double>, SIMD4<Float>, Float)] = [
            ("quarter", 0, .pi / 2, SIMD3(0, 0, 1), SIMD4(0.9, 0.3, 0.3, 1), 0),
            ("half", 0, .pi, SIMD3(0, 0, 1), SIMD4(0.3, 0.9, 0.3, 1), 12),
            ("three-quarter", 0, 1.5 * .pi, SIMD3(0, 0, 1), SIMD4(0.3, 0.3, 0.9, 1), 24),
        ]
        for (label, startA, endA, normal, color, dx) in arcDefs {
            if let arc = Curve3D.arcOfEllipse(
                center: SIMD3(0, 0, 0), normal: normal,
                majorRadius: 5, minorRadius: 3,
                startAngle: startA, endAngle: endA
            ) {
                let params = uniformParameters(curve: arc, count: 60)
                let pts = arc.evaluateGrid(params).map {
                    SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
                }
                var body = polylineToBody(pts, id: "arc-\(label)", color: color)
                offsetBody(&body, dx: dx + 18, dy: 0, dz: 0)
                bodies.append(body)
            }
        }
        // Also show a full ellipse outline for reference
        if let fullEllipse = Curve3D.arcOfEllipse(
            center: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1),
            majorRadius: 5, minorRadius: 3,
            startAngle: 0, endAngle: 2 * .pi
        ) {
            let params = uniformParameters(curve: fullEllipse, count: 80)
            let pts = fullEllipse.evaluateGrid(params).map {
                SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
            }
            for dx: Float in [18, 30, 42] {
                var body = polylineToBody(pts, id: "ellipse-ref-\(dx)",
                                          color: SIMD4(0.4, 0.4, 0.4, 0.4))
                offsetBody(&body, dx: dx, dy: 0, dz: 0)
                bodies.append(body)
            }
        }
        descriptions.append("Ellipse arcs: 1/4, 1/2, 3/4")

        // --- Edge adjacentFaces + dihedralAngle: color faces sharing an edge ---
        if let box = Shape.box(width: 6, height: 6, depth: 6) {
            // Show the box semi-transparent
            let (boxBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "dihedral-box", color: SIMD4(0.6, 0.6, 0.6, 0.3),
                deflection: 0.02
            )
            if var boxBody {
                offsetBody(&boxBody, dx: 0, dy: 16, dz: 0)
                bodies.append(boxBody)
            }

            // Pick edge 0 and highlight its adjacent faces
            if let edge0 = box.edge(at: 0),
               let (face1, face2) = edge0.adjacentFaces(in: box) {
                // Highlight face1 in red
                let face1Shape = box.subShape(type: .face, index: face1.index)
                if let f1s = face1Shape {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        f1s, id: "dihedral-f1", color: SIMD4(0.9, 0.3, 0.3, 0.8),
                        deflection: 0.02
                    )
                    if var body {
                        offsetBody(&body, dx: 0, dy: 16, dz: 0)
                        bodies.append(body)
                    }
                }
                // Highlight face2 in blue
                if let f2 = face2 {
                    let face2Shape = box.subShape(type: .face, index: f2.index)
                    if let f2s = face2Shape {
                        let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                            f2s, id: "dihedral-f2", color: SIMD4(0.3, 0.3, 0.9, 0.8),
                            deflection: 0.02
                        )
                        if var body {
                            offsetBody(&body, dx: 0, dy: 16, dz: 0)
                            bodies.append(body)
                        }
                    }

                    // Show dihedral angle
                    if let angle = edge0.dihedralAngle(between: face1, and: f2) {
                        let degrees = angle * 180.0 / .pi
                        descriptions.append(String(format: "Dihedral: %.0f°", degrees))
                    }
                }

                // Show the edge itself as a bold line
                let ep = edge0.endpoints
                let start = SIMD3<Float>(Float(ep.start.x), Float(ep.start.y), Float(ep.start.z))
                let end = SIMD3<Float>(Float(ep.end.x), Float(ep.end.y), Float(ep.end.z))
                var edgeBody = ViewportBody(
                    id: "dihedral-edge", vertexData: [], indices: [],
                    edges: [[start, end]], color: SIMD4(1, 1, 0.3, 1)
                )
                offsetBody(&edgeBody, dx: 0, dy: 16, dz: 0)
                bodies.append(edgeBody)
            }

            // Show all edges with dihedral angles — color by angle
            let allEdges = box.edges()
            var angleCount = 0
            for (i, edge) in allEdges.enumerated() {
                if let (f1, f2) = edge.adjacentFaces(in: box), let f2 = f2 {
                    if let _ = edge.dihedralAngle(between: f1, and: f2) {
                        angleCount += 1
                    }
                }
                // Draw each edge
                let ep = edge.endpoints
                let s = SIMD3<Float>(Float(ep.start.x), Float(ep.start.y), Float(ep.start.z))
                let e = SIMD3<Float>(Float(ep.end.x), Float(ep.end.y), Float(ep.end.z))
                var eb = ViewportBody(
                    id: "dihedral-edge-\(i)", vertexData: [], indices: [],
                    edges: [[s, e]], color: SIMD4(0.9, 0.9, 0.3, 1)
                )
                offsetBody(&eb, dx: 10, dy: 16, dz: 0)
                bodies.append(eb)
            }
            descriptions.append("\(angleCount)/\(allEdges.count) edges have angles")
        }

        // --- convertedToBezier: cylinder before/after ---
        if let cyl = Shape.cylinder(radius: 3, height: 5) {
            let origEdges = cyl.subShapeCount(ofType: .edge)
            let origFaces = cyl.subShapeCount(ofType: .face)
            let (orig, _) = CADFileLoader.shapeToBodyAndMetadata(
                cyl, id: "bezier-orig", color: SIMD4(0.6, 0.6, 0.6, 0.6),
                deflection: 0.02
            )
            if var orig {
                offsetBody(&orig, dx: 0, dy: 30, dz: 0)
                bodies.append(orig)
            }

            if let bezier = cyl.convertedToBezier {
                let newEdges = bezier.subShapeCount(ofType: .edge)
                let newFaces = bezier.subShapeCount(ofType: .face)
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    bezier, id: "bezier-result", color: SIMD4(0.3, 0.8, 0.6, 0.85),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 12, dy: 30, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("Bezier: \(origFaces)F/\(origEdges)E → \(newFaces)F/\(newEdges)E")
            }
        }

        // --- curveOnSurfaceCheck: validate a complex shape ---
        if let torus = Shape.torus(majorRadius: 5, minorRadius: 2) {
            if let check = torus.curveOnSurfaceCheck {
                descriptions.append(String(format: "pcurve check: max dev=%.1e", check.maxDistance))
            } else {
                descriptions.append("pcurve check: n/a")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.44: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.45: N-Side Filling, Self-Intersection, Wire Ordering

    /// Demonstrates FillingSurface, selfIntersection, and WireOrder.
    static func fillingAndSelfIntersection() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- FillingSurface: fill a hole bounded by 4 edges with a raised interior point ---
        if let box = Shape.box(width: 10, height: 10, depth: 0.1) {
            let allEdges = box.edges()
            // Use the first 4 edges (bottom face boundary)
            if allEdges.count >= 4 {
                let filling = FillingSurface()
                for i in 0..<4 {
                    filling.add(edge: allEdges[i], continuity: .c0)
                }
                // Add a raised interior point to make it interesting
                filling.add(point: SIMD3(5, 5, 4))

                if let face = filling.build() {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        face, id: "filling-face", color: SIMD4(0.3, 0.7, 0.9, 0.85),
                        deflection: 0.02
                    )
                    if let body { bodies.append(body) }

                    if let g0 = filling.g0Error {
                        descriptions.append(String(format: "N-fill G0=%.1e", g0))
                    } else {
                        descriptions.append("N-fill: built")
                    }
                }
            }
        }

        // Second filling: triangle from 3 wire edges
        let triPts: [SIMD3<Double>] = [
            SIMD3(0, 0, 0), SIMD3(8, 0, 0), SIMD3(4, 7, 0)
        ]
        if let triWire = Wire.polygon3D(triPts, closed: true) {
            let triEdges = Shape.fromWire(triWire)?.edges() ?? []
            if triEdges.count >= 3 {
                let filling = FillingSurface()
                for edge in triEdges {
                    filling.add(edge: edge, continuity: .c0)
                }
                filling.add(point: SIMD3(4, 2.5, 3))

                if let face = filling.build() {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        face, id: "filling-tri", color: SIMD4(0.9, 0.5, 0.3, 0.85),
                        deflection: 0.02
                    )
                    if var body {
                        offsetBody(&body, dx: 14, dy: 0, dz: 0)
                        bodies.append(body)
                    }
                    descriptions.append("tri-fill")
                }
            }
        }

        // --- Self-intersection detection ---
        // Clean box — should have no self-intersections
        if let box = Shape.box(width: 5, height: 5, depth: 5) {
            if let result = box.selfIntersection() {
                descriptions.append("box SI: \(result.overlapCount)")
            } else {
                descriptions.append("box SI: n/a")
            }

            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "si-box", color: SIMD4(0.5, 0.8, 0.5, 0.7),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 0, dy: 14, dz: 0)
                bodies.append(body)
            }
        }

        // --- WireOrder: scramble edges and reorder them ---
        // Define 4 edges of a square in scrambled order
        let scrambled: [(start: SIMD3<Double>, end: SIMD3<Double>)] = [
            (SIMD3(0, 0, 0), SIMD3(8, 0, 0)),       // edge 0: bottom
            (SIMD3(8, 8, 0), SIMD3(0, 8, 0)),       // edge 1: top (reversed)
            (SIMD3(0, 8, 0), SIMD3(0, 0, 0)),       // edge 2: left
            (SIMD3(8, 0, 0), SIMD3(8, 8, 0)),       // edge 3: right
        ]

        // Show scrambled edges with numbered colors
        let edgeColors: [SIMD4<Float>] = [
            SIMD4(1, 0.3, 0.3, 1), SIMD4(0.3, 1, 0.3, 1),
            SIMD4(0.3, 0.3, 1, 1), SIMD4(1, 1, 0.3, 1),
        ]
        for (i, edge) in scrambled.enumerated() {
            let s = SIMD3<Float>(Float(edge.start.x), Float(edge.start.y), Float(edge.start.z))
            let e = SIMD3<Float>(Float(edge.end.x), Float(edge.end.y), Float(edge.end.z))
            var body = ViewportBody(
                id: "wireorder-scrambled-\(i)", vertexData: [], indices: [],
                edges: [[s, e]], color: edgeColors[i]
            )
            offsetBody(&body, dx: 14, dy: 14, dz: 0)
            bodies.append(body)
        }

        if let order = WireOrder.analyze(edges: scrambled) {
            let indices = order.orderedEdges.map {
                "\($0.isReversed ? "-" : "")\($0.originalIndex)"
            }
            descriptions.append("WireOrder(\(order.status)): [\(indices.joined(separator: ","))]")
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.45: " + descriptions.joined(separator: " | ")
        )
    }

    // MARK: - v0.46: Edge Concavity, Local Prism, Volume Inertia

    /// Demonstrates edgeConcavities, localPrism, volumeInertia, and surfaceInertia.
    static func concavityAndInertia() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Edge concavity: color box edges by convex/concave/tangent ---
        if let box = Shape.box(width: 6, height: 6, depth: 6) {
            let (boxBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "concavity-box", color: SIMD4(0.6, 0.6, 0.6, 0.4),
                deflection: 0.02
            )
            if let boxBody { bodies.append(boxBody) }

            if let concavities = box.edgeConcavities() {
                var convexCount = 0, concaveCount = 0, tangentCount = 0
                for (edge, concavity) in concavities {
                    let color: SIMD4<Float>
                    switch concavity {
                    case .convex:
                        color = SIMD4(0.3, 0.9, 0.3, 1); convexCount += 1
                    case .concave:
                        color = SIMD4(0.9, 0.3, 0.3, 1); concaveCount += 1
                    case .tangent:
                        color = SIMD4(0.9, 0.9, 0.3, 1); tangentCount += 1
                    }
                    let ep = edge.endpoints
                    let s = SIMD3<Float>(Float(ep.start.x), Float(ep.start.y), Float(ep.start.z))
                    let e = SIMD3<Float>(Float(ep.end.x), Float(ep.end.y), Float(ep.end.z))
                    bodies.append(ViewportBody(
                        id: "concavity-e\(edge.index)", vertexData: [], indices: [],
                        edges: [[s, e]], color: color
                    ))
                }
                descriptions.append("Concavity: \(convexCount)cvx \(concaveCount)ccv \(tangentCount)tan")
            }
        }

        // Filleted box — has tangent edges at the fillet-face transitions
        if let box = Shape.box(width: 6, height: 6, depth: 6),
           let filleted = box.filleted(radius: 1.0) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                filleted, id: "concavity-fillet", color: SIMD4(0.6, 0.6, 0.6, 0.4),
                deflection: 0.02
            )
            if var body {
                offsetBody(&body, dx: 12, dy: 0, dz: 0)
                bodies.append(body)
            }

            if let concavities = filleted.edgeConcavities() {
                var cvx = 0, ccv = 0, tan = 0
                for (edge, concavity) in concavities {
                    let color: SIMD4<Float>
                    switch concavity {
                    case .convex: color = SIMD4(0.3, 0.9, 0.3, 1); cvx += 1
                    case .concave: color = SIMD4(0.9, 0.3, 0.3, 1); ccv += 1
                    case .tangent: color = SIMD4(0.9, 0.9, 0.3, 1); tan += 1
                    }
                    let ep = edge.endpoints
                    let s = SIMD3<Float>(Float(ep.start.x), Float(ep.start.y), Float(ep.start.z))
                    let e = SIMD3<Float>(Float(ep.end.x), Float(ep.end.y), Float(ep.end.z))
                    var eb = ViewportBody(
                        id: "concavity-f-e\(edge.index)", vertexData: [], indices: [],
                        edges: [[s, e]], color: color
                    )
                    offsetBody(&eb, dx: 12, dy: 0, dz: 0)
                    bodies.append(eb)
                }
                descriptions.append("Filleted: \(cvx)cvx \(ccv)ccv \(tan)tan")
            }
        }

        // --- Local prism: extrude a face profile ---
        if let rectWire = Wire.rectangle(width: 4, height: 3),
           let face = Shape.face(from: rectWire) {
            // Simple upward prism
            if let prism = face.localPrism(direction: SIMD3(0, 0, 6)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    prism, id: "prism-simple", color: SIMD4(0.4, 0.6, 0.9, 0.85),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 0, dy: 14, dz: 0)
                    bodies.append(body)
                }
            }

            // Prism with translation (skewed)
            if let prism = face.localPrism(direction: SIMD3(0, 0, 6),
                                            translation: SIMD3(3, 2, 0)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    prism, id: "prism-skewed", color: SIMD4(0.9, 0.5, 0.3, 0.85),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 10, dy: 14, dz: 0)
                    bodies.append(body)
                }
            }
            descriptions.append("localPrism: straight + skewed")
        }

        // --- Volume inertia: box with principal axes visualization ---
        if let box = Shape.box(width: 10, height: 6, depth: 4) {
            let (boxBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "inertia-box", color: SIMD4(0.5, 0.7, 0.8, 0.6),
                deflection: 0.02
            )
            if var boxBody {
                offsetBody(&boxBody, dx: 0, dy: 28, dz: 0)
                bodies.append(boxBody)
            }

            if let vi = box.volumeInertia {
                let cm = SIMD3<Float>(Float(vi.centerOfMass.x), Float(vi.centerOfMass.y), Float(vi.centerOfMass.z))
                // Center of mass marker
                var marker = makeMarker(at: cm, radius: 0.3, id: "inertia-cm",
                                         color: SIMD4(1, 1, 1, 1))
                offsetBody(&marker, dx: 0, dy: 28, dz: 0)
                bodies.append(marker)

                // Principal axes as colored lines from center of mass
                let axisColors: [SIMD4<Float>] = [
                    SIMD4(1, 0.2, 0.2, 1), // axis 1 — red
                    SIMD4(0.2, 1, 0.2, 1), // axis 2 — green
                    SIMD4(0.2, 0.2, 1, 1), // axis 3 — blue
                ]
                let axes = [vi.principalAxes.0, vi.principalAxes.1, vi.principalAxes.2]
                for (i, axis) in axes.enumerated() {
                    let dir = SIMD3<Float>(Float(axis.x), Float(axis.y), Float(axis.z))
                    let len = Float(vi.gyrationRadii[i]) * 0.5
                    let start = cm - dir * len
                    let end = cm + dir * len
                    var axisBody = ViewportBody(
                        id: "inertia-axis-\(i)", vertexData: [], indices: [],
                        edges: [[start, end]], color: axisColors[i]
                    )
                    offsetBody(&axisBody, dx: 0, dy: 28, dz: 0)
                    bodies.append(axisBody)
                }

                descriptions.append(String(format: "Vol=%.0f CM=(%.0f,%.0f,%.0f)",
                    vi.volume, vi.centerOfMass.x, vi.centerOfMass.y, vi.centerOfMass.z))
                descriptions.append(String(format: "Moments: %.0f/%.0f/%.0f",
                    vi.principalMoments.x, vi.principalMoments.y, vi.principalMoments.z))
            }

            // Surface inertia too
            if let si = box.surfaceInertia {
                descriptions.append(String(format: "Area=%.0f", si.area))
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "v0.46: " + descriptions.joined(separator: " | ")
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

    // MARK: - v0.47: Local Revolution, Draft Prism & Validation

    /// Local revolution, draft prism, constrained fill, and BRepCheck validation.
    static func localOpsAndValidation() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Local revolution: revolve a rectangular profile around Y axis ---
        if let rectWire = Wire.rectangle(width: 2, height: 1),
           let face = Shape.face(from: rectWire) {
            // Move profile away from axis so revolution creates a ring
            let profile = face.translated(by: SIMD3(3, 0, 0))
            if let revolved = profile?.localRevolution(
                axisOrigin: SIMD3(0, 0, 0),
                axisDirection: SIMD3(0, 1, 0),
                angle: .pi * 1.5 // 270 degrees
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    revolved, id: "local-revol", color: SIMD4(0.4, 0.7, 0.9, 0.85),
                    deflection: 0.05
                )
                if let body { bodies.append(body) }
                descriptions.append("LocalRevol: rect profile 270°")
            }

            // Revolution with angular offset
            if let profile2 = face.translated(by: SIMD3(3, 0, 0)),
               let revolvedOffset = profile2.localRevolution(
                axisOrigin: SIMD3(0, 0, 0),
                axisDirection: SIMD3(0, 1, 0),
                angle: .pi,
                angularOffset: .pi / 4 // Start 45° offset
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    revolvedOffset, id: "local-revol-offset",
                    color: SIMD4(0.9, 0.5, 0.3, 0.85), deflection: 0.05
                )
                if var body {
                    offsetBody(&body, dx: 12, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("LocalRevol: 180° with 45° offset")
            }
        }

        // --- Draft prism: tapered extrusion from a face ---
        if let circWire = Wire.circle(radius: 2),
           let circShape = Shape.face(from: circWire),
           let circFace = circShape.faces().first {
            // Two-height draft prism
            if let draft = circFace.draftPrism(height1: 5, height2: 3, angle: .pi / 12) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    draft, id: "draft-prism-2h", color: SIMD4(0.3, 0.8, 0.5, 0.85),
                    deflection: 0.05
                )
                if var body {
                    offsetBody(&body, dx: 0, dy: 12, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("DraftPrism: 2-height tapered")
            }

            // Single-height draft prism
            if let draft2 = circFace.draftPrism(height: 6, angle: .pi / 8) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    draft2, id: "draft-prism-1h", color: SIMD4(0.8, 0.4, 0.7, 0.85),
                    deflection: 0.05
                )
                if var body {
                    offsetBody(&body, dx: 12, dy: 12, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("DraftPrism: single-height tapered")
            }
        }

        // --- Constrained fill: BSpline surface from boundary edges ---
        if let box = Shape.box(width: 6, height: 6, depth: 6) {
            let edges = box.edges()
            if edges.count >= 4 {
                // Use first 4 edges of a box for a 4-sided constrained fill
                if let filled = Shape.constrainedFill(
                    edge1: edges[0], edge2: edges[1],
                    edge3: edges[2], edge4: edges[3]
                ) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        filled, id: "constrained-fill-4",
                        color: SIMD4(0.9, 0.7, 0.2, 0.85), deflection: 0.05
                    )
                    if var body {
                        offsetBody(&body, dx: 0, dy: 24, dz: 0)
                        bodies.append(body)
                    }
                    if let info = filled.constrainedFillInfo {
                        descriptions.append("ConstrainedFill: deg \(info.uDegree)×\(info.vDegree) poles \(info.uPoles)×\(info.vPoles)")
                    } else {
                        descriptions.append("ConstrainedFill: 4-edge surface")
                    }
                }

                // 3-sided fill
                if let filled3 = Shape.constrainedFill(
                    edge1: edges[0], edge2: edges[1], edge3: edges[2]
                ) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        filled3, id: "constrained-fill-3",
                        color: SIMD4(0.5, 0.9, 0.7, 0.85), deflection: 0.05
                    )
                    if var body {
                        offsetBody(&body, dx: 12, dy: 24, dz: 0)
                        bodies.append(body)
                    }
                    descriptions.append("ConstrainedFill: 3-edge surface")
                }
            }
        }

        // --- BRepCheck: validate shapes ---
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            let check = box.checkResult
            let statuses = box.detailedCheckStatuses
            descriptions.append("BRepCheck box: valid=\(check.isValid) errors=\(check.errorCount) statuses=\(statuses.count)")

            // Check individual faces
            let faces = box.faces()
            if let firstFace = faces.first {
                let faceCheck = firstFace.faceCheckResult
                descriptions.append("Face check: valid=\(faceCheck.isValid)")
            }
        }

        // Deliberately check an empty/degenerate scenario
        if let sphere = Shape.sphere(radius: 3) {
            let check = sphere.checkResult
            descriptions.append("BRepCheck sphere: valid=\(check.isValid) errors=\(check.errorCount)")
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.48: Split Ops, Line Intersection & Extrema

    /// Split operations, line-shape intersection, distance extrema, and shape upgrade.
    static func splitOpsAndExtrema() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Local pipe: sweep circle along a helix spine ---
        if let circWire = Wire.circle(radius: 0.5),
           let circFace = Shape.face(from: circWire),
           let spine = Wire.helix(radius: 3, pitch: 2.0, turns: 3) {
            if let pipe = circFace.localPipe(along: spine) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    pipe, id: "local-pipe", color: SIMD4(0.4, 0.7, 0.9, 0.85),
                    deflection: 0.1
                )
                if let body { bodies.append(body) }
                descriptions.append("LocalPipe: circle swept along helix")
            }
        }

        // --- Local linear form: translation sweep ---
        if let rectWire = Wire.rectangle(width: 2, height: 1),
           let face = Shape.face(from: rectWire) {
            if let linear = face.localLinearForm(
                direction: SIMD3(1, 0, 1),
                from: SIMD3(0, 0, 0),
                to: SIMD3(5, 0, 5)
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    linear, id: "linear-form", color: SIMD4(0.9, 0.6, 0.3, 0.85),
                    deflection: 0.05
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("LinearForm: rect swept along diagonal")
            }
        }

        // --- Split edge: split a box edge at midpoint ---
        if let box = Shape.box(width: 6, height: 6, depth: 6) {
            let edgesBefore = box.edges().count
            if let split = box.splitEdge(at: 0, parameter: 0.5) {
                let edgesAfter = split.edges().count
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    split, id: "split-edge", color: SIMD4(0.5, 0.8, 0.4, 0.85),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 0, dy: 14, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("SplitEdge: \(edgesBefore)→\(edgesAfter) edges")
            }
        }

        // --- Intersect line: shoot a line through a sphere and find hit points ---
        if let sphere = Shape.sphere(radius: 3) {
            let hits = sphere.intersectLine(
                origin: SIMD3(-10, 0, 0),
                direction: SIMD3(1, 0, 0)
            )
            // Show sphere
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sphere, id: "intersect-sphere", color: SIMD4(0.6, 0.6, 0.9, 0.4),
                deflection: 0.05
            )
            if var body {
                offsetBody(&body, dx: 14, dy: 14, dz: 0)
                bodies.append(body)
            }
            // Show hit points as markers
            for (i, hit) in hits.enumerated() {
                let p = SIMD3<Float>(Float(hit.point.x) + 14, Float(hit.point.y) + 14, Float(hit.point.z))
                bodies.append(makeMarker(at: p, radius: 0.4, id: "hit-\(i)",
                                         color: SIMD4(1, 0.2, 0.2, 1)))
            }
            // Show the line itself
            let lineStart = SIMD3<Float>(-10 + 14, 0 + 14, 0)
            let lineEnd = SIMD3<Float>(10 + 14, 0 + 14, 0)
            bodies.append(ViewportBody(
                id: "intersect-line", vertexData: [], indices: [],
                edges: [[lineStart, lineEnd]], color: SIMD4(1, 0.4, 0.4, 1)
            ))
            descriptions.append("IntersectLine: \(hits.count) hits on sphere")
        }

        // --- Edge-edge extrema: distance between edges of two shapes ---
        if let box1 = Shape.box(width: 4, height: 4, depth: 4),
           let box2orig = Shape.box(width: 3, height: 3, depth: 3),
           let box2 = box2orig.translated(by: SIMD3(8, 0, 0)) {
            if let extrema = box1.edgeEdgeExtrema(edgeIndex1: 0, other: box2, edgeIndex2: 0) {
                let p1 = SIMD3<Float>(Float(extrema.pointOnEdge1.x), Float(extrema.pointOnEdge1.y), Float(extrema.pointOnEdge1.z))
                let p2 = SIMD3<Float>(Float(extrema.pointOnEdge2.x), Float(extrema.pointOnEdge2.y), Float(extrema.pointOnEdge2.z))

                // Show both boxes
                let (b1, _) = CADFileLoader.shapeToBodyAndMetadata(
                    box1, id: "ee-box1", color: SIMD4(0.7, 0.7, 0.7, 0.5), deflection: 0.02
                )
                let (b2, _) = CADFileLoader.shapeToBodyAndMetadata(
                    box2, id: "ee-box2", color: SIMD4(0.7, 0.7, 0.7, 0.5), deflection: 0.02
                )
                if var b1 { offsetBody(&b1, dx: 0, dy: 28, dz: 0); bodies.append(b1) }
                if var b2 { offsetBody(&b2, dx: 0, dy: 28, dz: 0); bodies.append(b2) }

                // Draw distance line
                let offset = SIMD3<Float>(0, 28, 0)
                bodies.append(ViewportBody(
                    id: "ee-dist-line", vertexData: [], indices: [],
                    edges: [[p1 + offset, p2 + offset]], color: SIMD4(1, 0.8, 0.2, 1)
                ))
                bodies.append(makeMarker(at: p1 + offset, radius: 0.3, id: "ee-p1", color: SIMD4(1, 0.3, 0.3, 1)))
                bodies.append(makeMarker(at: p2 + offset, radius: 0.3, id: "ee-p2", color: SIMD4(0.3, 1, 0.3, 1)))
                descriptions.append("EdgeEdgeExtrema: dist=\(String(format: "%.2f", extrema.distance)) parallel=\(extrema.isParallel)")
            }
        }

        // --- Point-face extrema: closest point on a face to an external point ---
        if let box = Shape.box(width: 6, height: 6, depth: 6) {
            let testPoint = SIMD3<Double>(3, 10, 3)
            if let pf = box.pointFaceExtrema(point: testPoint, faceIndex: 0) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    box, id: "pf-box", color: SIMD4(0.6, 0.6, 0.6, 0.5), deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 28, dz: 0)
                    bodies.append(body)
                }
                let offset = SIMD3<Float>(14, 28, 0)
                let tp = SIMD3<Float>(Float(testPoint.x), Float(testPoint.y), Float(testPoint.z)) + offset
                let fp = SIMD3<Float>(Float(pf.pointOnFace.x), Float(pf.pointOnFace.y), Float(pf.pointOnFace.z)) + offset
                bodies.append(makeMarker(at: tp, radius: 0.4, id: "pf-test", color: SIMD4(1, 0.3, 0.3, 1)))
                bodies.append(makeMarker(at: fp, radius: 0.4, id: "pf-face", color: SIMD4(0.3, 1, 0.3, 1)))
                bodies.append(ViewportBody(
                    id: "pf-line", vertexData: [], indices: [],
                    edges: [[tp, fp]], color: SIMD4(1, 0.8, 0.2, 1)
                ))
                descriptions.append("PointFaceExtrema: dist=\(String(format: "%.2f", pf.distance))")
            }
        }

        // --- Divided closed faces: split cylinder's closed face ---
        if let cyl = Shape.cylinder(radius: 3, height: 8) {
            let facesBefore = cyl.faces().count
            if let divided = cyl.dividedClosedFaces() {
                let facesAfter = divided.faces().count
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    divided, id: "divided-closed", color: SIMD4(0.7, 0.5, 0.9, 0.85),
                    deflection: 0.05
                )
                if var body {
                    offsetBody(&body, dx: 28, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("DividedClosed: cyl faces \(facesBefore)→\(facesAfter)")
            }
        }

        // --- Divided by continuity: split at C1 breaks ---
        if let box = Shape.box(width: 4, height: 4, depth: 4),
           let filleted = box.filleted(radius: 0.8) {
            let edgesBefore = filleted.edges().count
            if let divided = filleted.dividedByContinuity(criterion: .c2) {
                let edgesAfter = divided.edges().count
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    divided, id: "divided-cont", color: SIMD4(0.5, 0.8, 0.6, 0.85),
                    deflection: 0.02
                )
                if var body {
                    offsetBody(&body, dx: 28, dy: 14, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("DividedByContinuity(C2): edges \(edgesBefore)→\(edgesAfter)")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.49: Extrema, Curve Joining, Free Bounds & Analysis

    /// Point-edge/edge-face extrema, curve joining, free bounds analysis,
    /// surface UV projection, and curve analysis.
    static func extremaAndCurveAnalysis() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Point-edge extrema: closest point from external point to box edge ---
        if let box = Shape.box(width: 8, height: 4, depth: 4) {
            let testPoint = SIMD3<Double>(6, 5, 2)
            if let pe = box.pointEdgeExtrema(point: testPoint, edgeIndex: 0) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    box, id: "pe-box", color: SIMD4(0.6, 0.6, 0.6, 0.5), deflection: 0.02
                )
                if let body { bodies.append(body) }
                let tp = SIMD3<Float>(Float(testPoint.x), Float(testPoint.y), Float(testPoint.z))
                let ep = SIMD3<Float>(Float(pe.pointOnEdge.x), Float(pe.pointOnEdge.y), Float(pe.pointOnEdge.z))
                bodies.append(makeMarker(at: tp, radius: 0.3, id: "pe-test", color: SIMD4(1, 0.3, 0.3, 1)))
                bodies.append(makeMarker(at: ep, radius: 0.3, id: "pe-edge", color: SIMD4(0.3, 1, 0.3, 1)))
                bodies.append(ViewportBody(
                    id: "pe-line", vertexData: [], indices: [],
                    edges: [[tp, ep]], color: SIMD4(1, 0.8, 0.2, 1)
                ))
                descriptions.append("PointEdge: dist=\(String(format: "%.2f", pe.distance)) param=\(String(format: "%.2f", pe.parameter))")
            }
        }

        // --- Edge-face extrema: distance from cylinder edge to box face ---
        if let cyl = Shape.cylinder(radius: 1.5, height: 6),
           let boxOrig = Shape.box(width: 4, height: 4, depth: 4),
           let box = boxOrig.translated(by: SIMD3(8, 0, 0)) {
            if let ef = cyl.edgeFaceExtrema(edgeIndex: 0, other: box, faceIndex: 0) {
                let (cylBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                    cyl, id: "ef-cyl", color: SIMD4(0.5, 0.7, 0.9, 0.7), deflection: 0.05
                )
                let (boxBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                    box, id: "ef-box", color: SIMD4(0.7, 0.7, 0.7, 0.5), deflection: 0.02
                )
                if var cylBody { offsetBody(&cylBody, dx: 0, dy: 14, dz: 0); bodies.append(cylBody) }
                if var boxBody { offsetBody(&boxBody, dx: 0, dy: 14, dz: 0); bodies.append(boxBody) }

                if !ef.isParallel {
                    let offset = SIMD3<Float>(0, 14, 0)
                    let pe = SIMD3<Float>(Float(ef.pointOnEdge.x), Float(ef.pointOnEdge.y), Float(ef.pointOnEdge.z)) + offset
                    let pf = SIMD3<Float>(Float(ef.pointOnFace.x), Float(ef.pointOnFace.y), Float(ef.pointOnFace.z)) + offset
                    bodies.append(makeMarker(at: pe, radius: 0.2, id: "ef-pe", color: SIMD4(1, 0.3, 0.3, 1)))
                    bodies.append(makeMarker(at: pf, radius: 0.2, id: "ef-pf", color: SIMD4(0.3, 1, 0.3, 1)))
                    bodies.append(ViewportBody(
                        id: "ef-line", vertexData: [], indices: [],
                        edges: [[pe, pf]], color: SIMD4(1, 0.8, 0.2, 1)
                    ))
                    descriptions.append("EdgeFace: dist=\(String(format: "%.2f", ef.distance)) UV=(\(String(format: "%.2f", ef.faceUV.x)), \(String(format: "%.2f", ef.faceUV.y)))")
                } else {
                    descriptions.append("EdgeFace: parallel")
                }
            }
        }

        // --- Curve joining: join 3 edge curves into one BSpline ---
        if let box = Shape.box(width: 6, height: 4, depth: 3) {
            let edges = box.edges()
            // Get curves from first 3 consecutive edges
            var curves: [Curve3D] = []
            for i in 0..<min(3, edges.count) {
                if let c = edges[i].approximatedCurve() {
                    curves.append(c)
                }
            }
            if curves.count >= 2 {
                // Show individual edge curves (before join)
                for (i, curve) in curves.enumerated() {
                    let pts = curve.samplePoints(first: 0, last: 1, maxPoints: 50)
                    let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y) + 28, Float($0.z)) }
                    if !floatPts.isEmpty {
                        let colors: [SIMD4<Float>] = [
                            SIMD4(1, 0.3, 0.3, 1), SIMD4(0.3, 1, 0.3, 1), SIMD4(0.3, 0.3, 1, 1)
                        ]
                        bodies.append(polylineToBody(floatPts, id: "curve-pre-\(i)",
                                                     color: colors[i % colors.count]))
                    }
                }

                // Try to join them
                if let joined = Curve3D.joined(curves: curves) {
                    let pts = joined.samplePoints(first: 0, last: 1, maxPoints: 100)
                    let floatPts = pts.map { SIMD3<Float>(Float($0.x) + 14, Float($0.y) + 28, Float($0.z)) }
                    if !floatPts.isEmpty {
                        bodies.append(polylineToBody(floatPts, id: "curve-joined",
                                                     color: SIMD4(1, 0.8, 0.2, 1)))
                    }
                    descriptions.append("CurveJoin: \(curves.count) curves → 1 BSpline")
                }
            }
        }

        // --- Curve analysis: project point and validate range ---
        if let box = Shape.box(width: 6, height: 6, depth: 6) {
            let edges = box.edges()
            if let firstEdge = edges.first,
               let curve = firstEdge.approximatedCurve() {
                // Project a point onto the curve
                let testPt = SIMD3<Double>(5, 5, 0)
                let proj = curve.projectPoint(testPt)

                let offset = SIMD3<Float>(20, 0, 0)
                let tp = SIMD3<Float>(Float(testPt.x), Float(testPt.y), Float(testPt.z)) + offset
                let pp = SIMD3<Float>(Float(proj.point.x), Float(proj.point.y), Float(proj.point.z)) + offset
                bodies.append(makeMarker(at: tp, radius: 0.25, id: "proj-test", color: SIMD4(1, 0.3, 0.3, 1)))
                bodies.append(makeMarker(at: pp, radius: 0.25, id: "proj-pt", color: SIMD4(0.3, 1, 0.3, 1)))
                bodies.append(ViewportBody(
                    id: "proj-line", vertexData: [], indices: [],
                    edges: [[tp, pp]], color: SIMD4(1, 0.8, 0.2, 1)
                ))

                // Show the curve
                let samplePts = curve.samplePoints(first: 0, last: 1, maxPoints: 50)
                let floatPts = samplePts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + offset }
                if !floatPts.isEmpty {
                    bodies.append(polylineToBody(floatPts, id: "proj-curve", color: SIMD4(0.5, 0.7, 1, 1)))
                }

                // Validate range
                let vr = curve.validateRange(first: -1.0, last: 2.0)
                descriptions.append("CurveProject: dist=\(String(format: "%.2f", proj.distance)) param=\(String(format: "%.2f", proj.parameter))")
                descriptions.append("ValidateRange: [\(String(format: "%.2f", vr.first)), \(String(format: "%.2f", vr.last))] adjusted=\(vr.wasAdjusted)")
            }
        }

        // --- Surface UV projection: project 3D points onto a sphere surface ---
        if let sphere = Shape.sphere(radius: 4) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sphere, id: "uv-sphere", color: SIMD4(0.5, 0.7, 0.9, 0.3), deflection: 0.05
            )
            if var body {
                offsetBody(&body, dx: 0, dy: 42, dz: 0)
                bodies.append(body)
            }

            // Create a Surface for UV projection
            let surface = Surface.sphere(center: SIMD3(0, 0, 0), radius: 4)
            if let surface {
                let testPoints: [SIMD3<Double>] = [
                    SIMD3(4, 0, 0), SIMD3(0, 4, 0), SIMD3(0, 0, 4),
                    SIMD3(2.83, 2.83, 0), SIMD3(0, 2.83, 2.83)
                ]
                for (i, pt) in testPoints.enumerated() {
                    let uv = surface.valueOfUV(point: pt)
                    let marker = SIMD3<Float>(Float(pt.x), Float(pt.y) + 42, Float(pt.z))
                    bodies.append(makeMarker(at: marker, radius: 0.3, id: "uv-pt-\(i)",
                                             color: SIMD4(1, 0.4, 0.2, 1)))
                    if i == 0 {
                        descriptions.append("SurfaceUV: gap=\(String(format: "%.4f", uv.gap)) uv=(\(String(format: "%.2f", uv.uv.x)), \(String(format: "%.2f", uv.uv.y)))")
                    }
                }
            }
        }

        // --- Free bounds analysis: analyze a shell with holes ---
        if let box = Shape.box(width: 10, height: 10, depth: 10) {
            // Create a shell by removing a face (using cut to punch a hole)
            if let cyl = Shape.cylinder(radius: 2, height: 12),
               let holed = box.subtracting(cyl) {
                let analysis = holed.freeBoundsAnalysis(tolerance: 0.01)
                descriptions.append("FreeBounds: total=\(analysis.totalCount) closed=\(analysis.closedCount) open=\(analysis.openCount)")

                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    holed, id: "fb-shape", color: SIMD4(0.6, 0.8, 0.5, 0.7), deflection: 0.05
                )
                if var body {
                    offsetBody(&body, dx: 14, dy: 42, dz: 0)
                    bodies.append(body)
                }

                // Show closed free bound wires if any
                for i in 0..<analysis.closedCount {
                    if let info = holed.closedFreeBoundInfo(tolerance: 0.01, index: i) {
                        descriptions.append("  Bound \(i): area=\(String(format: "%.1f", info.area)) perim=\(String(format: "%.1f", info.perimeter)) notches=\(info.notchCount)")
                    }
                }
            }
        }

        // --- BSpline restriction: simplify a filleted box ---
        if let box = Shape.box(width: 6, height: 6, depth: 6),
           let filleted = box.filleted(radius: 1.0) {
            let edgesBefore = filleted.edges().count
            if let simplified = filleted.bsplineRestriction(
                tol3d: 0.1, maxDegree: 4, maxSegments: 20
            ) {
                let edgesAfter = simplified.edges().count
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    simplified, id: "bspline-restricted",
                    color: SIMD4(0.8, 0.6, 0.4, 0.85), deflection: 0.05
                )
                if var body {
                    offsetBody(&body, dx: 28, dy: 42, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("BSplineRestrict: edges \(edgesBefore)→\(edgesAfter) (maxDeg=4)")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.50: Conic Arcs, Polyhedral Distance, Surfaces & Analysis

    /// Hyperbola/parabola arcs, curve splitting, polyhedral distance,
    /// surface construction, nearest plane fitting, and wire vertex analysis.
    static func conicsAndPolyDistance() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Arc of hyperbola ---
        if let hyp = Curve3D.arcOfHyperbola(
            majorRadius: 3, minorRadius: 1.5,
            alpha1: -1.0, alpha2: 1.0
        ) {
            let pts = hyp.samplePoints(first: -1.0, last: 1.0, maxPoints: 60)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            if !floatPts.isEmpty {
                bodies.append(polylineToBody(floatPts, id: "hyp-arc", color: SIMD4(0.9, 0.4, 0.2, 1)))
            }
            descriptions.append("Hyperbola arc: a=3 b=1.5 t∈[-1,1]")
        }

        // --- Arc of parabola ---
        if let para = Curve3D.arcOfParabola(
            center: SIMD3(0, 8, 0),
            focalDistance: 1.0,
            alpha1: -3.0, alpha2: 3.0
        ) {
            let pts = para.samplePoints(first: -3.0, last: 3.0, maxPoints: 60)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            if !floatPts.isEmpty {
                bodies.append(polylineToBody(floatPts, id: "para-arc", color: SIMD4(0.2, 0.7, 0.9, 1)))
            }
            descriptions.append("Parabola arc: f=1.0 t∈[-3,3]")
        }

        // --- Curve splitting: split a circle at midpoint ---
        if let circWire = Wire.circle(radius: 3),
           let edge = Shape.face(from: circWire)?.edges().first,
           let curve = edge.approximatedCurve() {
            if let split = curve.splitAt(parameter: 0.5) {
                let pts1 = split.first.samplePoints(first: 0, last: 1, maxPoints: 40)
                let pts2 = split.second.samplePoints(first: 0, last: 1, maxPoints: 40)
                let dx: Float = 10
                let fp1 = pts1.map { SIMD3<Float>(Float($0.x) + dx, Float($0.y), Float($0.z)) }
                let fp2 = pts2.map { SIMD3<Float>(Float($0.x) + dx, Float($0.y), Float($0.z)) }
                if !fp1.isEmpty { bodies.append(polylineToBody(fp1, id: "split-1", color: SIMD4(1, 0.3, 0.3, 1))) }
                if !fp2.isEmpty { bodies.append(polylineToBody(fp2, id: "split-2", color: SIMD4(0.3, 1, 0.3, 1))) }
                descriptions.append("CurveSplit: circle → 2 segments (red/green)")
            }
        }

        // --- Polyhedral distance: fast approximate distance between shapes ---
        if let sphere = Shape.sphere(radius: 2),
           let boxOrig = Shape.box(width: 3, height: 3, depth: 3),
           let box = boxOrig.translated(by: SIMD3(8, 0, 0)) {
            // Mesh them first (shapeToBody triggers tessellation)
            let (sBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                sphere, id: "poly-sphere", color: SIMD4(0.5, 0.7, 0.9, 0.6), deflection: 0.1
            )
            let (bBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "poly-box", color: SIMD4(0.7, 0.7, 0.7, 0.6), deflection: 0.05
            )
            if var sBody { offsetBody(&sBody, dx: 0, dy: 18, dz: 0); bodies.append(sBody) }
            if var bBody { offsetBody(&bBody, dx: 0, dy: 18, dz: 0); bodies.append(bBody) }

            if let dist = sphere.polyhedralDistance(to: box) {
                let offset = SIMD3<Float>(0, 18, 0)
                let p1 = SIMD3<Float>(Float(dist.point1.x), Float(dist.point1.y), Float(dist.point1.z)) + offset
                let p2 = SIMD3<Float>(Float(dist.point2.x), Float(dist.point2.y), Float(dist.point2.z)) + offset
                bodies.append(makeMarker(at: p1, radius: 0.2, id: "poly-p1", color: SIMD4(1, 0.3, 0.3, 1)))
                bodies.append(makeMarker(at: p2, radius: 0.2, id: "poly-p2", color: SIMD4(0.3, 1, 0.3, 1)))
                bodies.append(ViewportBody(
                    id: "poly-line", vertexData: [], indices: [],
                    edges: [[p1, p2]], color: SIMD4(1, 0.8, 0.2, 1)
                ))
                descriptions.append("PolyDist: \(String(format: "%.3f", dist.distance)) (approx)")
            }
        }

        // --- Nearest plane fitting ---
        let points: [SIMD3<Double>] = [
            SIMD3(0, 0, 0), SIMD3(5, 0, 0.1), SIMD3(5, 5, -0.1),
            SIMD3(0, 5, 0.2), SIMD3(2.5, 2.5, -0.05)
        ]
        if let plane = Shape.nearestPlane(to: points) {
            for (i, pt) in points.enumerated() {
                let p = SIMD3<Float>(Float(pt.x) + 20, Float(pt.y), Float(pt.z))
                bodies.append(makeMarker(at: p, radius: 0.2, id: "plane-pt-\(i)", color: SIMD4(0.3, 0.8, 1, 1)))
            }
            let center = SIMD3<Float>(Float(plane.origin.x) + 20, Float(plane.origin.y), Float(plane.origin.z))
            let normalEnd = center + SIMD3<Float>(Float(plane.normal.x), Float(plane.normal.y), Float(plane.normal.z)) * 3
            bodies.append(ViewportBody(
                id: "plane-normal", vertexData: [], indices: [],
                edges: [[center, normalEnd]], color: SIMD4(1, 0.5, 0.2, 1)
            ))
            descriptions.append("NearestPlane: dev=\(String(format: "%.4f", plane.maxDeviation)) n=(\(String(format: "%.2f", plane.normal.x)), \(String(format: "%.2f", plane.normal.y)), \(String(format: "%.2f", plane.normal.z)))")
        }

        // --- Wire vertex analysis ---
        if let box = Shape.box(width: 6, height: 6, depth: 6) {
            let wva = box.wireVertexAnalysis()
            var statusCounts: [String: Int] = [:]
            for i in 0..<wva.edgeCount {
                let s = box.wireVertexStatus(index: i)
                let name = "\(s)"
                statusCounts[name, default: 0] += 1
            }
            descriptions.append("WireVertex: \(wva.edgeCount) edges, done=\(wva.isDone)")
            let summary = statusCounts.map { "\($0.key):\($0.value)" }.sorted().joined(separator: " ")
            if !summary.isEmpty { descriptions.append("  Statuses: \(summary)") }
        }

        // --- History tracking demo ---
        if let box = Shape.box(width: 4, height: 4, depth: 4),
           let filleted = box.filleted(radius: 0.5),
           let history = Shape.History() {
            history.addModified(initial: box, modified: filleted)
            descriptions.append("History: hasModified=\(history.hasModified) modCount=\(history.modifiedCount(of: box))")
        }

        // --- Conical surface from axis ---
        if let cone = Surface.conicalSurface(semiAngle: .pi / 6, radius: 2) {
            let uv = cone.valueOfUV(point: SIMD3(2, 0, 0))
            descriptions.append("ConicalSurface: gap=\(String(format: "%.4f", uv.gap)) at (2,0,0)")
        }

        // --- Trimmed cylinder surface ---
        if let trimCyl = Surface.trimmedCylinder(radius: 2, height: 6) {
            let ksr = trimCyl.knotSplitting()
            descriptions.append("TrimmedCyl: knotSplit U=\(ksr.uSplitCount) V=\(ksr.vSplitCount)")
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.51: Transforms, Topology, Conics, 2D Lines, AnaFillet

    /// GC transforms, topology builders, 3-point conics, 2D line construction, and 2D analytical fillet.
    static func transformsAndTopology() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Section A: GC Transforms ---
        // Reference box
        if let refBox = Shape.box(width: 2, height: 2, depth: 2) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                refBox, id: "gc-ref", color: SIMD4(0.6, 0.6, 0.6, 0.5)
            )
            if let body { bodies.append(body) }

            // Mirror about point (6, 0, 0)
            if let mirrored = refBox.mirroredAboutPoint(SIMD3(6, 0, 0)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    mirrored, id: "gc-mirror-pt", color: SIMD4(0.9, 0.3, 0.3, 1)
                )
                if let body { bodies.append(body) }
                bodies.append(makeMarker(at: SIMD3(6, 0, 0), radius: 0.15, id: "gc-mirror-pt-m",
                                         color: SIMD4(1, 1, 0, 1)))
                descriptions.append("MirrorPoint: box mirrored about (6,0,0)")
            }

            // Mirror about Y axis
            if let mirrored = refBox.mirroredAboutAxis(origin: .zero, direction: SIMD3(0, 1, 0)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    mirrored, id: "gc-mirror-ax", color: SIMD4(0.3, 0.9, 0.3, 1)
                )
                if var body {
                    offsetBody(&body, dx: 0, dy: 6, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("MirrorAxis: box mirrored about Y axis")
            }

            // Scale about origin by 1.5x
            if let scaled = refBox.scaledAboutPoint(.zero, factor: 1.5) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    scaled, id: "gc-scaled", color: SIMD4(0.3, 0.5, 0.9, 0.7)
                )
                if var body {
                    offsetBody(&body, dx: 0, dy: 0, dz: 6)
                    bodies.append(body)
                }
                descriptions.append("Scale: 1.5× about origin")
            }

            // Translate from→to
            if let moved = refBox.translated(from: SIMD3(0, 0, 0), to: SIMD3(8, 4, 0)) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    moved, id: "gc-translate", color: SIMD4(0.9, 0.6, 0.2, 1)
                )
                if let body { bodies.append(body) }
                bodies.append(ViewportBody(
                    id: "gc-translate-arrow", vertexData: [], indices: [],
                    edges: [[SIMD3(1, 1, 1), SIMD3(8, 4, 0)]],
                    color: SIMD4(0.9, 0.6, 0.2, 1)
                ))
                descriptions.append("Translate: (0,0,0)→(8,4,0)")
            }
        }

        // --- Section B: 3-Point Conics ---
        let ellipseOffset = SIMD3<Float>(18, 0, 0)

        // Ellipse through 3 points
        let eS1 = SIMD3<Double>(3, 0, 0), eS2 = SIMD3<Double>(0, 2, 0), eCenter = SIMD3<Double>(0, 0, 0)
        if let ellipse = Curve3D.ellipseThreePoints(s1: eS1, s2: eS2, center: eCenter) {
            let dom = ellipse.domain
            let pts = ellipse.samplePoints(first: dom.lowerBound, last: dom.upperBound, maxPoints: 80)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + ellipseOffset }
            if !floatPts.isEmpty {
                bodies.append(polylineToBody(floatPts, id: "conic-ellipse", color: SIMD4(0.2, 0.7, 1, 1)))
            }
            for (label, pt) in [("eS1", eS1), ("eS2", eS2), ("eC", eCenter)] {
                let p = SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z)) + ellipseOffset
                bodies.append(makeMarker(at: p, radius: 0.15, id: "conic-\(label)", color: SIMD4(1, 0.8, 0.2, 1)))
            }
            descriptions.append("Ellipse3Pt: s1=(3,0,0) s2=(0,2,0) c=origin")
        }

        // Hyperbola through 3 points
        let hypOffset = SIMD3<Float>(18, 8, 0)
        let hS1 = SIMD3<Double>(4, 0, 0), hS2 = SIMD3<Double>(0, 2, 0), hCenter = SIMD3<Double>(0, 0, 0)
        if let hyp = Curve3D.hyperbolaThreePoints(s1: hS1, s2: hS2, center: hCenter) {
            let dom = hyp.domain
            let lo = max(dom.lowerBound, -2.0)
            let hi = min(dom.upperBound, 2.0)
            let pts = hyp.samplePoints(first: lo, last: hi, maxPoints: 80)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + hypOffset }
            if !floatPts.isEmpty {
                bodies.append(polylineToBody(floatPts, id: "conic-hyp", color: SIMD4(1, 0.4, 0.6, 1)))
            }
            for (label, pt) in [("hS1", hS1), ("hS2", hS2), ("hC", hCenter)] {
                let p = SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z)) + hypOffset
                bodies.append(makeMarker(at: p, radius: 0.15, id: "conic-\(label)", color: SIMD4(1, 0.8, 0.2, 1)))
            }
            descriptions.append("Hyperbola3Pt: s1=(4,0,0) s2=(0,2,0) c=origin")
        }

        // --- Section C: 2D Line Construction ---
        let lineOffset = SIMD3<Float>(0, 14, 0)
        let lp1 = SIMD2<Double>(0, 0), lp2 = SIMD2<Double>(8, 3)
        if let line = Curve2D.lineThroughPoints(lp1, lp2) {
            let pts = line.drawUniform(pointCount: 2)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) + lineOffset }
            if floatPts.count >= 2 {
                bodies.append(polylineToBody(floatPts, id: "line2d-through",
                                             color: SIMD4(0.2, 0.8, 0.4, 1)))
            }
            let m1 = SIMD3<Float>(Float(lp1.x), Float(lp1.y), 0) + lineOffset
            let m2 = SIMD3<Float>(Float(lp2.x), Float(lp2.y), 0) + lineOffset
            bodies.append(makeMarker(at: m1, radius: 0.12, id: "line2d-p1", color: SIMD4(1, 0.3, 0.3, 1)))
            bodies.append(makeMarker(at: m2, radius: 0.12, id: "line2d-p2", color: SIMD4(1, 0.3, 0.3, 1)))
            descriptions.append("Line2D: through (0,0)→(8,3)")
        }

        // Parallel line
        if let parallel = Curve2D.lineParallel(point: lp1, direction: SIMD2(8, 3), distance: 2.0) {
            let pts = parallel.drawUniform(pointCount: 2)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) + lineOffset }
            if floatPts.count >= 2 {
                bodies.append(polylineToBody(floatPts, id: "line2d-parallel",
                                             color: SIMD4(0.8, 0.5, 0.9, 1)))
            }
            descriptions.append("LineParallel: offset 2.0 from reference")
        }

        // --- Section D: Topology Builders ---
        // solidFromShell: build a box, get its shell, reconstruct solid
        if let box = Shape.box(width: 3, height: 3, depth: 3) {
            let shells = box.shells
            if let shell = shells.first,
               let solid = Shape.solidFromShell(shell) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    solid, id: "topo-solid", color: SIMD4(0.4, 0.8, 0.6, 1)
                )
                if var body {
                    offsetBody(&body, dx: -8, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("SolidFromShell: box shell → solid")
            }
        }

        // wireFromEdges: extract edges from a box, assemble into wire
        if let box = Shape.box(width: 4, height: 2, depth: 2) {
            let allEdges = box.edges()
            let subset = Array(allEdges.prefix(4))
            if !subset.isEmpty, let wire = Wire.wireFromEdges(subset) {
                let wBody = wireToBody(wire, id: "topo-wire", color: SIMD4(0.9, 0.7, 0.2, 1))
                var mBody = wBody
                offsetBody(&mBody, dx: -8, dy: 6, dz: 0)
                bodies.append(mBody)
                descriptions.append("WireFromEdges: 4 box edges → wire")
            }
        }

        // --- Section E: Analytical 2D Fillet ---
        let filletOffset = SIMD3<Float>(0, -8, 0)
        // Two line segments meeting at origin at 90°
        if let cornerWire = Wire.polygon3D(
            [SIMD3(-5, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 5, 0)], closed: false
        ) {
            if let result = Shape.anaFillet(
                wire: cornerWire, edgeIndex: 0,
                planeNormal: SIMD3(0, 0, 1), radius: 1.5
            ) {
                // Render trimmed edges
                for (i, edgeShape) in [(0, result.edge1), (1, result.edge2)].enumerated() {
                    let polylines = edgeShape.1.allEdgePolylines(deflection: 0.05)
                    for pl in polylines {
                        let floatPts = pl.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + filletOffset }
                        if floatPts.count >= 2 {
                            bodies.append(polylineToBody(floatPts, id: "fillet-edge-\(i)",
                                                         color: SIMD4(0.6, 0.8, 1, 1)))
                        }
                    }
                }
                // Render fillet arc
                let filletPolylines = result.fillet.allEdgePolylines(deflection: 0.02)
                for pl in filletPolylines {
                    let floatPts = pl.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + filletOffset }
                    if floatPts.count >= 2 {
                        bodies.append(polylineToBody(floatPts, id: "fillet-arc",
                                                     color: SIMD4(1, 0.4, 0.2, 1)))
                    }
                }
                descriptions.append("AnaFillet: r=1.5 between 90° edges")
            }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.52: BRepFill, Fillet, Healing, 2D Curve Tools

    /// BRepFill suite, iterative 2D fillet, healing utilities, and 2D curve analysis tools.
    static func brepFillAndHealing() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Section A: BRepFill_Generator — ruled shell between wire sections ---
        if let circle1 = Wire.circle(radius: 2),
           let circle2 = Wire.circle(origin: SIMD3(0, 0, 6), radius: 3.5) {
            if let shell = Shape.ruledShell(from: [circle1, circle2]) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    shell, id: "fill-ruled", color: SIMD4(0.4, 0.7, 0.9, 0.8)
                )
                if let body { bodies.append(body) }
                descriptions.append("RuledShell: circle r=2 → r=3.5")
            }
        }

        // --- Section B: BRepFill_Draft — tapered extrusion ---
        if let profile = Wire.polygon([
            SIMD2(0, 0), SIMD2(3, 0), SIMD2(3, 2), SIMD2(0, 2)
        ]) {
            if let draft = Shape.draft(
                wire: profile,
                direction: SIMD3(0, 0, 1),
                angle: .pi / 12,  // 15° taper
                length: 5
            ) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    draft, id: "fill-draft", color: SIMD4(0.8, 0.5, 0.3, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: 10, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("Draft: rect profile, 15° taper, h=5")
            }
        }

        // --- Section C: BRepFill_Pipe with error metric ---
        if let spine = Wire.helix(radius: 3, pitch: 2, turns: 3),
           let profile = Wire.polygon([
               SIMD2(-0.5, -0.5), SIMD2(0.5, -0.5),
               SIMD2(0.5, 0.5), SIMD2(-0.5, 0.5)
           ]) {
            if let result = Shape.pipeSweep(spine: spine, profile: profile) {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    result.shape, id: "fill-pipe", color: SIMD4(0.6, 0.8, 0.4, 0.8)
                )
                if var body {
                    offsetBody(&body, dx: 20, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("PipeSweep: square on helix, err=\(String(format: "%.4f", result.errorOnSurface))")
            }
        }

        // --- Section D: BRepFill_CompatibleWires ---
        if let w1 = Wire.polygon([
            SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 4), SIMD2(0, 4)
        ]),
           let w2 = Wire.circle(origin: SIMD3(2, 2, 6), radius: 2) {
            if let compatible = Shape.compatibleWires([w1, w2]) {
                descriptions.append("CompatibleWires: \(compatible.count) wires normalized")
                // Loft the compatible wires into a ruled shell
                if compatible.count >= 2,
                   let shell = Shape.ruledShell(from: compatible) {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        shell, id: "fill-compat", color: SIMD4(0.7, 0.4, 0.8, 0.8)
                    )
                    if var body {
                        offsetBody(&body, dx: 0, dy: 12, dz: 0)
                        bodies.append(body)
                    }
                }
            }
        }

        // --- Section E: BRepFill_OffsetWire ---
        if let face = Shape.face(from: Wire.polygon([
            SIMD2(0, 0), SIMD2(6, 0), SIMD2(6, 6), SIMD2(0, 6)
        ])!) {
            if let offsetShape = Shape.offsetWire(face: face.faces().first!, offset: -1.0) {
                let polylines = offsetShape.allEdgePolylines(deflection: 0.05)
                for (i, pl) in polylines.enumerated() {
                    let offset = SIMD3<Float>(10, 12, 0)
                    let floatPts = pl.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + offset }
                    if floatPts.count >= 2 {
                        bodies.append(polylineToBody(floatPts, id: "fill-offset-\(i)",
                                                     color: SIMD4(0.2, 0.9, 0.5, 1)))
                    }
                }
                // Show original outline too
                let origPolylines = face.allEdgePolylines(deflection: 0.05)
                for (i, pl) in origPolylines.enumerated() {
                    let offset = SIMD3<Float>(10, 12, 0)
                    let floatPts = pl.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + offset }
                    if floatPts.count >= 2 {
                        bodies.append(polylineToBody(floatPts, id: "fill-offset-orig-\(i)",
                                                     color: SIMD4(0.5, 0.5, 0.5, 0.6)))
                    }
                }
                descriptions.append("OffsetWire: square inset by 1.0")
            }
        }

        // --- Section F: ChFi2d_FilletAlgo (iterative fillet) ---
        // Two edges at 60° angle in a single wire
        if let angleWire = Wire.polygon3D(
            [SIMD3(-5, 0, 0), SIMD3(0, 0, 0), SIMD3(2.5, 4.33, 0)], closed: false
        ) {
            if let result = Shape.filletAlgo(
                wire: angleWire, edgeIndex: 0,
                planeNormal: SIMD3(0, 0, 1), radius: 1.0
            ) {
                let filletOffset = SIMD3<Float>(20, 12, 0)
                for (i, edgeShape) in [(0, result.edge1), (1, result.edge2)].enumerated() {
                    let polylines = edgeShape.1.allEdgePolylines(deflection: 0.02)
                    for pl in polylines {
                        let floatPts = pl.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + filletOffset }
                        if floatPts.count >= 2 {
                            bodies.append(polylineToBody(floatPts, id: "fillet2-edge-\(i)",
                                                         color: SIMD4(0.6, 0.8, 1, 1)))
                        }
                    }
                }
                let arcPolylines = result.fillet.allEdgePolylines(deflection: 0.01)
                for pl in arcPolylines {
                    let floatPts = pl.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) + filletOffset }
                    if floatPts.count >= 2 {
                        bodies.append(polylineToBody(floatPts, id: "fillet2-arc",
                                                     color: SIMD4(1, 0.3, 0.5, 1)))
                    }
                }
                descriptions.append("FilletAlgo: r=1.0 at 60°, \(result.resultCount) solutions")
            }
        }

        // --- Section G: Healing — shellSewing + builtFromFaces ---
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            // shellSewing
            if let _ = box.shellSewing(tolerance: 1e-3) {
                descriptions.append("ShellSewing: box sewn OK")
            }
            // builtFromFaces
            if let rebuilt = box.builtFromFaces() {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    rebuilt, id: "heal-built", color: SIMD4(0.5, 0.8, 0.7, 0.9)
                )
                if var body {
                    offsetBody(&body, dx: -10, dy: 12, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("BuildFromFaces: box faces → rebuilt shape")
            }
        }

        // --- Section H: Edge splitting ---
        if let box = Shape.box(width: 6, height: 2, depth: 2) {
            let allEdges = box.edges()
            if let firstEdge = allEdges.first {
                // Split at midpoint
                let midParam = 0.5
                let midPt = SIMD3<Double>(3, 0, 0) // approximate midpoint of first edge
                if let (_, _) = firstEdge.split(at: midParam, vertex: midPt) {
                    descriptions.append("EdgeSplit: edge → 2 halves at midpoint")
                }
            }
        }

        // --- Section I: Curve2D tools ---
        // isLinear check
        if let bspline = Curve2D.interpolate(
            through: [SIMD2(0, 0), SIMD2(5, 0), SIMD2(10, 0)],
            tangents: [:]) {
            if let result = bspline.isLinear(tolerance: 1e-3) {
                descriptions.append("IsLinear: \(result.isLinear), dev=\(String(format: "%.6f", result.deviation))")
            }
            // convertToLine
            let dom = bspline.domain
            if let conv = bspline.convertToLine(first: dom.lowerBound, last: dom.upperBound) {
                descriptions.append("ConvertToLine: dev=\(String(format: "%.6f", conv.deviation))")
            }
        }

        // simplifyBSpline
        if let complex = Curve2D.interpolate(
            through: [SIMD2(0, 0), SIMD2(2, 0.01), SIMD2(4, 0), SIMD2(6, -0.01), SIMD2(8, 0)],
            tangents: [:]) {
            let simplified = complex.simplifyBSpline(tolerance: 0.1)
            descriptions.append("SimplifyBSpline: \(simplified ? "simplified" : "unchanged")")
        }

        // Approx_Curve2d: approximate a circle as BSpline
        if let circle = Curve2D.circle(center: .zero, radius: 3) {
            let dom = circle.domain
            if let approx = circle.approximated(
                first: dom.lowerBound, last: dom.upperBound, maxDegree: 6
            ) {
                let pts = approx.drawAdaptive()
                let lineOffset = SIMD3<Float>(0, -8, 0)
                let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) + lineOffset }
                if !floatPts.isEmpty {
                    bodies.append(polylineToBody(floatPts, id: "approx-circle",
                                                 color: SIMD4(0.9, 0.6, 0.2, 1)))
                }
                descriptions.append("Approx2D: circle → BSpline (deg≤6)")
            }
        }

        // parameterAtLength
        if let line = Curve2D.lineThroughPoints(SIMD2(0, 0), SIMD2(10, 0)) {
            if let param = line.parameterAtLength(5.0) {
                let pt = line.point(at: param)
                descriptions.append("ParamAtLength: L=5 → u=\(String(format: "%.3f", param)) pt=(\(String(format: "%.1f", pt.x)),\(String(format: "%.1f", pt.y)))")
            }
        }

        // Tangent-constrained interpolation
        if let tangentCurve = Curve2D.interpolate(
            through: [SIMD2(0, 0), SIMD2(3, 2), SIMD2(6, 0), SIMD2(9, -1), SIMD2(12, 0)],
            tangents: [0: SIMD2(1, 1), 2: SIMD2(1, 0), 4: SIMD2(1, 1)]
        ) {
            let pts = tangentCurve.drawAdaptive()
            let curveOffset = SIMD3<Float>(15, -8, 0)
            let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) + curveOffset }
            if !floatPts.isEmpty {
                bodies.append(polylineToBody(floatPts, id: "tangent-interp",
                                             color: SIMD4(0.3, 0.8, 0.9, 1)))
            }
            // Mark the constrained points
            let controlPts: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(3, 2), SIMD2(6, 0), SIMD2(9, -1), SIMD2(12, 0)]
            for (i, p) in controlPts.enumerated() {
                bodies.append(makeMarker(
                    at: SIMD3<Float>(Float(p.x), Float(p.y), 0) + curveOffset,
                    radius: 0.15, id: "tang-pt-\(i)",
                    color: SIMD4(1, 0.4, 0.2, 1)))
            }
            descriptions.append("TangentInterp: 5 pts, 3 tangent constraints")
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.53: 2D Geometry Completions

    /// GccAna bisectors, line/circle solvers, IntAna2d intersections, Extrema2d, curvature analysis, Bisector_BisecAna.
    static func geometry2DCompletions() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // Helper: draw a 2D line solution as a segment in 3D (Z=0)
        func drawLine(_ sol: Curve2DLineSolution, id: String, color: SIMD4<Float>,
                      offset: SIMD3<Float> = .zero, length: Float = 10) {
            let p = SIMD3<Float>(Float(sol.point.x), Float(sol.point.y), 0) + offset
            let d = SIMD3<Float>(Float(sol.direction.x), Float(sol.direction.y), 0) * length
            bodies.append(polylineToBody([p - d, p + d], id: id, color: color))
        }

        // Helper: draw a circle solution as a polyline
        func drawCircle(_ center: SIMD2<Double>, _ radius: Double, id: String,
                        color: SIMD4<Float>, offset: SIMD3<Float> = .zero, segments: Int = 64) {
            var pts: [SIMD3<Float>] = []
            for i in 0...segments {
                let t = Double(i) / Double(segments) * 2 * .pi
                let x = Float(center.x + radius * cos(t))
                let y = Float(center.y + radius * sin(t))
                pts.append(SIMD3(x, y, 0) + offset)
            }
            bodies.append(polylineToBody(pts, id: id, color: color))
        }

        // --- Section A: GccAna Bisectors ---
        let bisecOff = SIMD3<Float>(0, 0, 0)

        // Point-point perpendicular bisector
        let bp1 = SIMD2<Double>(-3, 0), bp2 = SIMD2<Double>(3, 0)
        if let bisec = GccAnaBisector.ofPoints(bp1, bp2) {
            drawLine(bisec, id: "bisec-pp", color: SIMD4(0.2, 0.8, 0.4, 1), offset: bisecOff, length: 4)
            bodies.append(makeMarker(at: SIMD3(Float(bp1.x), Float(bp1.y), 0) + bisecOff,
                                     radius: 0.15, id: "bisec-pp-p1", color: SIMD4(1, 0.3, 0.3, 1)))
            bodies.append(makeMarker(at: SIMD3(Float(bp2.x), Float(bp2.y), 0) + bisecOff,
                                     radius: 0.15, id: "bisec-pp-p2", color: SIMD4(1, 0.3, 0.3, 1)))
            descriptions.append("BisecPP: perpendicular bisector of (-3,0)-(3,0)")
        }

        // Line-line angle bisectors
        let llBisecs = GccAnaBisector.ofLines(
            line1Point: .zero, line1Dir: SIMD2(1, 0),
            line2Point: .zero, line2Dir: simd_normalize(SIMD2<Double>(1, 1))
        )
        for (i, b) in llBisecs.enumerated() {
            let off = bisecOff + SIMD3(15, 0, 0)
            drawLine(b, id: "bisec-ll-\(i)", color: SIMD4(0.9, 0.5, 0.2, 1), offset: off, length: 5)
        }
        // Draw the reference lines
        let llOff = bisecOff + SIMD3<Float>(15, 0, 0)
        bodies.append(polylineToBody(
            [SIMD3(-5, 0, 0) + llOff, SIMD3(5, 0, 0) + llOff],
            id: "bisec-ll-ref1", color: SIMD4(0.5, 0.5, 0.5, 0.6)))
        let d45: Float = 5 * 0.7071
        bodies.append(polylineToBody(
            [SIMD3(-d45, -d45, 0) + llOff, SIMD3(d45, d45, 0) + llOff],
            id: "bisec-ll-ref2", color: SIMD4(0.5, 0.5, 0.5, 0.6)))
        descriptions.append("BisecLL: \(llBisecs.count) angle bisectors of X-axis & 45° line")

        // Circle-circle bisectors
        let ccBisecs = GccAnaBisector.ofCircles(
            center1: SIMD2(-3, 0), radius1: 2,
            center2: SIMD2(3, 0), radius2: 1.5
        )
        let ccOff = bisecOff + SIMD3<Float>(0, 12, 0)
        drawCircle(SIMD2(-3, 0), 2, id: "bisec-cc-c1", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: ccOff)
        drawCircle(SIMD2(3, 0), 1.5, id: "bisec-cc-c2", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: ccOff)
        for (i, b) in ccBisecs.enumerated() {
            if b.type == .circle {
                drawCircle(b.position, b.radius, id: "bisec-cc-\(i)",
                           color: SIMD4(0.3, 0.7, 1, 1), offset: ccOff)
            }
        }
        descriptions.append("BisecCC: \(ccBisecs.count) bisectors between r=2 & r=1.5 circles")

        // --- Section B: GccAna Line Solvers ---
        let lineOff = SIMD3<Float>(30, 0, 0)

        // Parallel line through point
        let parLines = Curve2DGcc.lineParallelThrough(
            point: SIMD2(0, 3),
            parallelTo: .zero, lineDir: SIMD2(1, 0)
        )
        bodies.append(polylineToBody(
            [SIMD3(-5, 0, 0) + lineOff, SIMD3(5, 0, 0) + lineOff],
            id: "gcc-ref-line", color: SIMD4(0.5, 0.5, 0.5, 0.6)))
        for (i, l) in parLines.enumerated() {
            drawLine(l, id: "gcc-par-\(i)", color: SIMD4(0.2, 0.9, 0.4, 1), offset: lineOff, length: 5)
        }
        bodies.append(makeMarker(at: SIMD3(0, 3, 0) + lineOff,
                                 radius: 0.15, id: "gcc-par-pt", color: SIMD4(1, 0.3, 0.3, 1)))
        descriptions.append("LinePar: parallel through (0,3)")

        // Perpendicular line through point
        let perpLines = Curve2DGcc.linePerpendicularThrough(
            point: SIMD2(2, 2),
            perpendicularTo: .zero, lineDir: SIMD2(1, 0)
        )
        for (i, l) in perpLines.enumerated() {
            drawLine(l, id: "gcc-perp-\(i)", color: SIMD4(0.9, 0.4, 0.6, 1), offset: lineOff, length: 3)
        }
        bodies.append(makeMarker(at: SIMD3(2, 2, 0) + lineOff,
                                 radius: 0.15, id: "gcc-perp-pt", color: SIMD4(1, 0.8, 0.2, 1)))
        descriptions.append("LinePerp: perpendicular through (2,2)")

        // Tangent lines to circle, parallel to X-axis
        let tanParLines = Curve2DGcc.linesTangentParallel(
            circleCenter: SIMD2(0, 0), circleRadius: 2,
            parallelTo: .zero, lineDir: SIMD2(1, 0)
        )
        let tanOff = lineOff + SIMD3(0, 10, 0)
        drawCircle(.zero, 2, id: "gcc-tan-circ", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: tanOff)
        for (i, l) in tanParLines.enumerated() {
            drawLine(l, id: "gcc-tanpar-\(i)", color: SIMD4(1, 0.6, 0.2, 1), offset: tanOff, length: 4)
        }
        descriptions.append("TanPar: \(tanParLines.count) tangent lines ∥ X-axis to r=2 circle")

        // --- Section C: IntAna2d Intersections ---
        let ixOff = SIMD3<Float>(0, -12, 0)

        // Line-line intersection
        let llIx = IntAna2d.intersectLines(
            line1Point: .zero, line1Dir: SIMD2(1, 0.5),
            line2Point: SIMD2(0, 3), line2Dir: SIMD2(1, -0.3)
        )
        let ld1 = simd_normalize(SIMD3<Float>(1, 0.5, 0)) * 6
        let ld2 = simd_normalize(SIMD3<Float>(1, -0.3, 0)) * 6
        bodies.append(polylineToBody(
            [SIMD3(0, 0, 0) + ixOff - ld1, SIMD3(0, 0, 0) + ixOff + ld1],
            id: "ix-ll-l1", color: SIMD4(0.5, 0.5, 0.5, 0.6)))
        bodies.append(polylineToBody(
            [SIMD3(0, 3, 0) + ixOff - ld2, SIMD3(0, 3, 0) + ixOff + ld2],
            id: "ix-ll-l2", color: SIMD4(0.5, 0.5, 0.5, 0.6)))
        for (i, pt) in llIx.enumerated() {
            bodies.append(makeMarker(
                at: SIMD3(Float(pt.point.x), Float(pt.point.y), 0) + ixOff,
                radius: 0.2, id: "ix-ll-\(i)", color: SIMD4(1, 0.2, 0.2, 1)))
        }
        descriptions.append("IntLL: \(llIx.count) line-line intersection")

        // Line-circle intersection
        let lcIx = IntAna2d.intersectLineCircle(
            linePoint: SIMD2(-5, 1), lineDir: SIMD2(1, 0),
            circleCenter: SIMD2(0, 0), circleRadius: 3
        )
        let lcOff = ixOff + SIMD3(15, 0, 0)
        drawCircle(.zero, 3, id: "ix-lc-c", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: lcOff)
        bodies.append(polylineToBody(
            [SIMD3(-5, 1, 0) + lcOff, SIMD3(5, 1, 0) + lcOff],
            id: "ix-lc-l", color: SIMD4(0.5, 0.5, 0.5, 0.6)))
        for (i, pt) in lcIx.enumerated() {
            bodies.append(makeMarker(
                at: SIMD3(Float(pt.point.x), Float(pt.point.y), 0) + lcOff,
                radius: 0.2, id: "ix-lc-\(i)", color: SIMD4(0.2, 1, 0.3, 1)))
        }
        descriptions.append("IntLC: \(lcIx.count) line-circle intersections")

        // Circle-circle intersection
        let ccIx = IntAna2d.intersectCircles(
            center1: SIMD2(-1.5, 0), radius1: 3,
            center2: SIMD2(1.5, 0), radius2: 3
        )
        let ccIxOff = ixOff + SIMD3(30, 0, 0)
        drawCircle(SIMD2(-1.5, 0), 3, id: "ix-cc-c1", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: ccIxOff)
        drawCircle(SIMD2(1.5, 0), 3, id: "ix-cc-c2", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: ccIxOff)
        for (i, pt) in ccIx.enumerated() {
            bodies.append(makeMarker(
                at: SIMD3(Float(pt.point.x), Float(pt.point.y), 0) + ccIxOff,
                radius: 0.2, id: "ix-cc-\(i)", color: SIMD4(1, 0.8, 0.2, 1)))
        }
        descriptions.append("IntCC: \(ccIx.count) circle-circle intersections")

        // --- Section D: Extrema2d ---
        let exOff = SIMD3<Float>(0, -24, 0)

        // Line-circle extrema
        let lcEx = Extrema2d.distanceBetweenLineAndCircle(
            linePoint: SIMD2(-6, 5), lineDir: SIMD2(1, 0),
            circleCenter: .zero, circleRadius: 2
        )
        drawCircle(.zero, 2, id: "ex-lc-c", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: exOff)
        bodies.append(polylineToBody(
            [SIMD3(-6, 5, 0) + exOff, SIMD3(6, 5, 0) + exOff],
            id: "ex-lc-l", color: SIMD4(0.5, 0.5, 0.5, 0.6)))
        for (i, ex) in lcEx.enumerated() {
            let p1 = SIMD3<Float>(Float(ex.point1.x), Float(ex.point1.y), 0) + exOff
            let p2 = SIMD3<Float>(Float(ex.point2.x), Float(ex.point2.y), 0) + exOff
            bodies.append(polylineToBody([p1, p2], id: "ex-lc-\(i)", color: SIMD4(1, 0.4, 0.2, 1)))
            bodies.append(makeMarker(at: p1, radius: 0.12, id: "ex-lc-m1-\(i)", color: SIMD4(1, 0.4, 0.2, 1)))
            bodies.append(makeMarker(at: p2, radius: 0.12, id: "ex-lc-m2-\(i)", color: SIMD4(1, 0.4, 0.2, 1)))
        }
        if let closest = lcEx.first {
            descriptions.append("ExtLC: d=\(String(format: "%.3f", closest.distance)) line↔circle")
        }

        // Parallel line detection
        let llEx = Extrema2d.distanceBetweenLines(
            line1Point: .zero, line1Dir: SIMD2(1, 0),
            line2Point: SIMD2(0, 4), line2Dir: SIMD2(1, 0)
        )
        descriptions.append("ExtLL: parallel=\(llEx.isParallel), \(llEx.results.count) results")

        // Curve-curve extrema: circle vs ellipse-like BSpline
        if let ellipse = Curve2D.interpolate(
            through: [SIMD2(4, 0), SIMD2(0, 2), SIMD2(-4, 0), SIMD2(0, -2)],
            tangents: [0: SIMD2(0, 1), 1: SIMD2(-1, 0), 2: SIMD2(0, -1), 3: SIMD2(1, 0)],
            closed: true
        ), let circle = Curve2D.circle(center: SIMD2(7, 0), radius: 1.5) {
            let ccExOff = exOff + SIMD3(15, 0, 0)
            // Draw the ellipse
            let ePts = ellipse.drawAdaptive()
            let eFloat = ePts.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) + ccExOff }
            if !eFloat.isEmpty { bodies.append(polylineToBody(eFloat, id: "ex-cc-e", color: SIMD4(0.5, 0.5, 0.5, 0.6))) }
            drawCircle(SIMD2(7, 0), 1.5, id: "ex-cc-c", color: SIMD4(0.5, 0.5, 0.5, 0.6), offset: ccExOff)

            let eDom = ellipse.domain
            let cDom = circle.domain
            let ccExResults = Extrema2d.distanceBetweenCurves(
                ellipse, first1: eDom.lowerBound, last1: eDom.upperBound,
                circle, first2: cDom.lowerBound, last2: cDom.upperBound
            )
            for (i, ex) in ccExResults.prefix(4).enumerated() {
                let p1 = SIMD3<Float>(Float(ex.point1.x), Float(ex.point1.y), 0) + ccExOff
                let p2 = SIMD3<Float>(Float(ex.point2.x), Float(ex.point2.y), 0) + ccExOff
                bodies.append(polylineToBody([p1, p2], id: "ex-cc-\(i)", color: SIMD4(0.3, 1, 0.5, 1)))
                bodies.append(makeMarker(at: p1, radius: 0.1, id: "ex-cc-m1-\(i)", color: SIMD4(0.3, 1, 0.5, 1)))
                bodies.append(makeMarker(at: p2, radius: 0.1, id: "ex-cc-m2-\(i)", color: SIMD4(0.3, 1, 0.5, 1)))
            }
            if let closest = ccExResults.first {
                descriptions.append("ExtCC: d=\(String(format: "%.3f", closest.distance)) ellipse↔circle, \(ccExResults.count) extrema")
            }
        }

        // --- Section E: Geom2dLProp — curvature analysis ---
        // Create a wavy curve with inflections and curvature extrema
        if let wave = Curve2D.interpolate(
            through: [SIMD2(0, 0), SIMD2(2, 3), SIMD2(5, -2), SIMD2(8, 1), SIMD2(11, -3), SIMD2(14, 0)],
            tangents: [:]
        ) {
            let lpOff = SIMD3<Float>(0, -36, 0)
            let pts = wave.drawAdaptive()
            let fPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) + lpOff }
            if !fPts.isEmpty { bodies.append(polylineToBody(fPts, id: "lp-wave", color: SIMD4(0.6, 0.6, 0.6, 1))) }

            let extrema = wave.curvatureExtremaDetailed()
            for (i, ex) in extrema.enumerated() {
                let pt = wave.point(at: ex.parameter)
                let color: SIMD4<Float> = ex.type == .curvatureMaximum
                    ? SIMD4(1, 0.3, 0.3, 1) : SIMD4(0.3, 0.3, 1, 1)
                bodies.append(makeMarker(
                    at: SIMD3(Float(pt.x), Float(pt.y), 0) + lpOff,
                    radius: 0.15, id: "lp-ext-\(i)", color: color))
            }
            let inflections = wave.inflectionPointsDetailed()
            for (i, inf) in inflections.enumerated() {
                let pt = wave.point(at: inf.parameter)
                bodies.append(makeMarker(
                    at: SIMD3(Float(pt.x), Float(pt.y), 0) + lpOff,
                    radius: 0.2, id: "lp-inf-\(i)", color: SIMD4(0.2, 0.9, 0.3, 1)))
            }
            descriptions.append("CurInf: \(extrema.count) curvature extrema (red=max,blue=min), \(inflections.count) inflections (green)")
        }

        // --- Section F: GccAna circle on-constraint ---
        let conOff = SIMD3<Float>(30, 12, 0)
        // Circles tangent to two lines with center on a third
        let conCircles = Curve2DGcc.circlesTangentToTwoLinesOnLine(
            line1Point: .zero, line1Dir: SIMD2(1, 0),
            line2Point: .zero, line2Dir: SIMD2(0, 1),
            centerOnPoint: .zero, centerOnDir: simd_normalize(SIMD2<Double>(1, 1))
        )
        // Draw reference: X-axis, Y-axis, 45° line
        bodies.append(polylineToBody(
            [SIMD3(-1, 0, 0) + conOff, SIMD3(8, 0, 0) + conOff],
            id: "con-ref-x", color: SIMD4(0.5, 0.5, 0.5, 0.5)))
        bodies.append(polylineToBody(
            [SIMD3(0, -1, 0) + conOff, SIMD3(0, 8, 0) + conOff],
            id: "con-ref-y", color: SIMD4(0.5, 0.5, 0.5, 0.5)))
        bodies.append(polylineToBody(
            [SIMD3(-1, -1, 0) + conOff, SIMD3(6, 6, 0) + conOff],
            id: "con-ref-45", color: SIMD4(0.5, 0.5, 0.5, 0.3)))
        for (i, c) in conCircles.enumerated() {
            drawCircle(c.center, c.radius, id: "con-circ-\(i)",
                       color: SIMD4(0.9, 0.5, 0.9, 1), offset: conOff)
            bodies.append(makeMarker(
                at: SIMD3(Float(c.center.x), Float(c.center.y), 0) + conOff,
                radius: 0.1, id: "con-center-\(i)", color: SIMD4(0.9, 0.5, 0.9, 1)))
        }
        descriptions.append("CircOnLine: \(conCircles.count) circles tangent to X&Y axes, center on 45°")

        // --- Section G: Bisector_BisecAna — point-point ---
        let bpOff = SIMD3<Float>(30, -12, 0)
        let bap1 = SIMD2<Double>(0, 0), bap2 = SIMD2<Double>(6, 4)
        if let bisecCurve = Curve2D.bisectorBetweenPoints(
            bap1, bap2,
            referencePoint: SIMD2(3, 2),
            direction1: SIMD2(1, 0), direction2: SIMD2(-1, 0)
        ) {
            let pts = bisecCurve.drawUniform(pointCount: 40)
            let fPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) + bpOff }
            if !fPts.isEmpty { bodies.append(polylineToBody(fPts, id: "bba-pp", color: SIMD4(0.4, 0.8, 1, 1))) }
            bodies.append(makeMarker(at: SIMD3(Float(bap1.x), Float(bap1.y), 0) + bpOff,
                                     radius: 0.15, id: "bba-pp-1", color: SIMD4(1, 0.3, 0.3, 1)))
            bodies.append(makeMarker(at: SIMD3(Float(bap2.x), Float(bap2.y), 0) + bpOff,
                                     radius: 0.15, id: "bba-pp-2", color: SIMD4(1, 0.3, 0.3, 1)))
            descriptions.append("BisecAna: point-point bisector (0,0)↔(6,4)")
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.54–v0.55: TDF/OCAF Framework & TDataStd Attributes

    /// Document framework: labels, transactions, undo/redo, attributes, tree nodes, named data.
    static func ocafFramework() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        // --- Section A: Document creation and label tree ---
        guard let doc = Document.create() else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Document.create() failed")
        }

        if let main = doc.mainLabel {
            descriptions.append("MainLabel: tag=\(main.tag) depth=\(main.depth) isRoot=\(main.isRoot)")

            // Create child labels
            if let child1 = main.findChild(tag: 1, create: true),
               let child2 = main.findChild(tag: 2, create: true),
               let child3 = main.findChild(tag: 3, create: true) {

                // Set names (TDataStd_Name)
                child1.setName("Part_A")
                child2.setName("Part_B")
                child3.setName("Assembly")

                descriptions.append("Children: \(main.childCount) created, hasChild=\(main.hasChild)")

                // --- Section B: TDF_Reference ---
                child3.setReference(to: child1)
                if let ref = child3.referencedLabel {
                    descriptions.append("Reference: child3 → tag=\(ref.tag)")
                }

                // --- Section C: Descendants ---
                // Create grandchildren
                if let gc1 = child3.findChild(tag: 1, create: true),
                   let gc2 = child3.findChild(tag: 2, create: true) {
                    gc1.setName("SubPart_1")
                    gc2.setName("SubPart_2")
                    let allDesc = main.descendants(allLevels: true)
                    let directDesc = main.descendants(allLevels: false)
                    descriptions.append("Descendants: \(directDesc.count) direct, \(allDesc.count) all levels")
                }

                // --- Section D: Transactions & Undo/Redo ---
                doc.setUndoLimit(10)

                doc.openTransaction()
                child1.setName("Part_A_Modified")
                doc.commitTransaction()

                doc.openTransaction()
                child2.setName("Part_B_Modified")
                doc.commitTransaction()

                descriptions.append("Transactions: undoLimit=\(doc.undoLimit) undos=\(doc.availableUndos) redos=\(doc.availableRedos)")

                doc.undo()
                descriptions.append("After undo: undos=\(doc.availableUndos) redos=\(doc.availableRedos)")

                doc.redo()
                descriptions.append("After redo: undos=\(doc.availableUndos) redos=\(doc.availableRedos)")

                // --- Section E: Label copy ---
                if let dest = main.findChild(tag: 10, create: true) {
                    doc.copyLabel(from: child1, to: dest)
                    descriptions.append("CopyLabel: child1 → tag=10, attrs=\(dest.attributeCount)")
                }

                // --- Section F: Modified tracking ---
                doc.clearModified()
                doc.setModified(child1)
                descriptions.append("Modified: child1=\(doc.isModified(child1)) child2=\(doc.isModified(child2))")

                // --- Section G: TDataStd Scalar Attributes (v0.55) ---
                child1.setInteger(42)
                child1.setReal(3.14159)
                child1.setAsciiString("hello_ocaf")
                child1.setComment("Test comment")
                descriptions.append("Scalars: int=\(child1.integer ?? -1) real=\(String(format: "%.5f", child1.real ?? 0)) str=\(child1.asciiString ?? "nil")")
                descriptions.append("Comment: \(child1.comment ?? "nil")")

                // --- Section H: Integer/Real Arrays (v0.55) ---
                child2.initIntegerArray(lower: 0, upper: 4)
                for i: Int32 in 0...4 { child2.setIntegerArrayValue(at: i, value: i * 10) }
                let arrVals = (0...4 as ClosedRange<Int32>).compactMap { child2.integerArrayValue(at: $0) }
                descriptions.append("IntArray: \(arrVals)")

                child2.initRealArray(lower: 1, upper: 3)
                child2.setRealArrayValue(at: 1, value: 1.1)
                child2.setRealArrayValue(at: 2, value: 2.2)
                child2.setRealArrayValue(at: 3, value: 3.3)
                if let bounds = child2.realArrayBounds {
                    descriptions.append("RealArray: bounds=[\(bounds.lower)..\(bounds.upper)]")
                }

                // --- Section I: TreeNode hierarchy (v0.55) ---
                child1.setTreeNode()
                child2.setTreeNode()
                child3.setTreeNode()
                child1.appendTreeChild(child2)
                child1.appendTreeChild(child3)
                descriptions.append("TreeNode: child1 children=\(child1.treeNodeChildCount) depth=\(child1.treeNodeDepth)")
                if let first = child1.treeNodeFirstChild {
                    descriptions.append("TreeNode: firstChild tag=\(first.tag) hasFather=\(first.treeNodeHasFather)")
                    if let next = first.treeNodeNext {
                        descriptions.append("TreeNode: nextSibling tag=\(next.tag)")
                    }
                }

                // --- Section J: NamedData key-value store (v0.55) ---
                child1.setNamedInteger("count", value: 7)
                child1.setNamedReal("weight", value: 12.5)
                child1.setNamedString("material", value: "aluminum")
                let hasCount = child1.hasNamedInteger("count")
                let weight = child1.namedReal("weight")
                let material = child1.namedString("material")
                descriptions.append("NamedData: count=\(child1.namedInteger("count") ?? -1) has=\(hasCount)")
                descriptions.append("NamedData: weight=\(String(format: "%.1f", weight ?? 0)) material=\(material ?? "nil")")
            }
        }

        // Show a reference box so the viewport isn't empty
        if let box = Shape.box(width: 4, height: 4, depth: 4) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                box, id: "ocaf-ref", color: SIMD4(0.5, 0.7, 0.9, 0.6)
            )
            if let body { bodies.append(body) }
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
    }

    // MARK: - v0.56–v0.58: Geometric Attributes, Persistence, STEP Control

    /// TDataXtd geometric attributes, TFunction framework, TNaming deep copy,
    /// OCAF persistence (binary/XML save/load), STEP mode-controlled I/O.
    static func ocafPersistenceAndSTEP() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var descriptions: [String] = []

        guard let doc = Document.create() else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Document.create() failed")
        }

        guard let main = doc.mainLabel else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "No main label")
        }

        // --- Section A: TDataXtd Shape + Position + Geometry attributes (v0.56) ---
        if let child1 = main.findChild(tag: 1, create: true) {
            child1.setName("GeomLabel")

            // Store a shape attribute
            if let box = Shape.box(width: 3, height: 3, depth: 3) {
                child1.setShapeAttribute(box)
                let hasShape = child1.hasShapeAttribute
                let retrieved = child1.shapeAttribute()
                descriptions.append("ShapeAttr: set=\(hasShape) retrieved=\(retrieved != nil)")

                // Show the retrieved shape
                if let shape = retrieved {
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        shape, id: "xtd-shape", color: SIMD4(0.5, 0.7, 0.9, 0.8)
                    )
                    if let body { bodies.append(body) }
                }
            }

            // Position attribute
            child1.setPositionAttribute(x: 1, y: 2, z: 3)
            if let pos = child1.positionAttribute() {
                descriptions.append("PositionAttr: (\(pos.x), \(pos.y), \(pos.z))")
            }

            // Geometry type
            child1.setGeometryType(.cylinder)
            if let gt = child1.geometryType() {
                descriptions.append("GeometryType: \(gt)")
            }

            // Point/Axis/Plane attributes
            child1.setPointAttribute(x: 0, y: 0, z: 0)
            child1.setAxisAttribute(originX: 0, originY: 0, originZ: 0,
                                     directionX: 0, directionY: 0, directionZ: 1)
            child1.setPlaneAttribute(originX: 0, originY: 0, originZ: 0,
                                      normalX: 0, normalY: 0, normalZ: 1)
            descriptions.append("Point/Axis/Plane attrs set on GeomLabel")
        }

        // --- Section B: Triangulation attribute (v0.56) ---
        if let child2 = main.findChild(tag: 2, create: true),
           let sphere = Shape.sphere(radius: 2) {
            child2.setTriangulationFromShape(sphere, deflection: 0.5)
            let nodes = child2.triangulationNodeCount
            let tris = child2.triangulationTriangleCount
            let defl = child2.triangulationDeflection
            descriptions.append("Triangulation: \(nodes) nodes, \(tris) tris, defl=\(String(format: "%.1f", defl))")

            // Show the sphere
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                sphere, id: "xtd-tri-sphere", color: SIMD4(0.4, 0.8, 0.5, 0.7)
            )
            if var body {
                offsetBody(&body, dx: 6, dy: 0, dz: 0)
                bodies.append(body)
            }
        }

        // --- Section C: TFunction framework (v0.56) ---
        if let funcLabel = main.findChild(tag: 3, create: true),
           let depLabel = main.findChild(tag: 4, create: true) {
            // Logbook
            funcLabel.setLogbook()
            funcLabel.logbookSetTouched(depLabel)
            let isModified = funcLabel.logbookIsModified(depLabel)
            let isEmpty = funcLabel.logbookIsEmpty
            descriptions.append("Logbook: touched=\(isModified) empty=\(isEmpty)")

            funcLabel.logbookClear()
            descriptions.append("Logbook: after clear empty=\(funcLabel.logbookIsEmpty)")

            // GraphNode
            funcLabel.setGraphNode()
            depLabel.setGraphNode()
            funcLabel.graphNodeAddNext(tag: depLabel.tag)
            funcLabel.setGraphNodeStatus(.succeeded)
            if let status = funcLabel.graphNodeStatus() {
                descriptions.append("GraphNode: status=\(status)")
            }

            // Function attribute
            funcLabel.setFunctionAttribute()
            descriptions.append("Function: isFailed=\(funcLabel.functionIsFailed)")
        }

        // --- Section D: TNaming deep copy (v0.56) ---
        if let cyl = Shape.cylinder(radius: 1.5, height: 4) {
            if let copy = cyl.deepCopy() {
                let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                    copy, id: "deep-copy", color: SIMD4(0.9, 0.6, 0.3, 0.8)
                )
                if var body {
                    offsetBody(&body, dx: -6, dy: 0, dz: 0)
                    bodies.append(body)
                }
                descriptions.append("DeepCopy: cylinder copied OK")
            }
        }

        // --- Section E: OCAF persistence (v0.57) ---
        // Create a document with format and test save/load
        if let binDoc = Document.create(format: "BinOcaf") {
            binDoc.defineFormatBin()
            if let docMain = binDoc.mainLabel,
               let testLabel = docMain.findChild(tag: 1, create: true) {
                testLabel.setName("Persistence_Test")
                testLabel.setInteger(99)
                testLabel.setReal(2.718)

                let tmpPath = NSTemporaryDirectory() + "test_ocaf.cbf"
                let saveStatus = binDoc.saveOCAF(to: tmpPath)
                descriptions.append("SaveOCAF: status=\(saveStatus) isSaved=\(binDoc.isSaved)")

                // Load it back
                let (loaded, loadStatus) = Document.loadOCAF(from: tmpPath)
                descriptions.append("LoadOCAF: status=\(loadStatus) loaded=\(loaded != nil)")
                if let loaded, let lMain = loaded.mainLabel,
                   let lChild = lMain.findChild(tag: 1) {
                    descriptions.append("Loaded: int=\(lChild.integer ?? -1) real=\(String(format: "%.3f", lChild.real ?? 0))")
                }

                // Clean up
                try? FileManager.default.removeItem(atPath: tmpPath)
            }

            // Format info
            if let fmt = binDoc.storageFormat {
                descriptions.append("Format: \(fmt)")
            }
            let rFormats = binDoc.readingFormats
            let wFormats = binDoc.writingFormats
            descriptions.append("Formats: \(rFormats.count) reading, \(wFormats.count) writing")
        }

        // --- Section F: STEP mode-controlled I/O (v0.58) ---
        if let box = Shape.box(width: 5, height: 5, depth: 5) {
            let tmpStep = NSTemporaryDirectory() + "test_v58.step"

            // Export with model type
            do {
                try box.writeSTEP(to: URL(fileURLWithPath: tmpStep), modelType: .manifoldSolidBrep)
                descriptions.append("STEP export: manifoldSolidBrep OK")
            } catch {
                descriptions.append("STEP export: \(error)")
            }

            // Root inspection
            let rootCount = Shape.stepRootCount(path: tmpStep)
            let shapeCount = Shape.stepShapeCount(path: tmpStep)
            descriptions.append("STEP inspect: \(rootCount) roots, \(shapeCount) shapes")

            // Import specific root
            if rootCount > 0 {
                do {
                    let imported = try Shape.loadSTEPRoot(fromPath: tmpStep, rootIndex: 1)
                    let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                        imported, id: "step-root", color: SIMD4(0.7, 0.5, 0.9, 0.8)
                    )
                    if var body {
                        offsetBody(&body, dx: 0, dy: 8, dz: 0)
                        bodies.append(body)
                    }
                    descriptions.append("STEP root import: OK")
                } catch {
                    descriptions.append("STEP root import: \(error)")
                }
            }

            // Mode-controlled document import
            let modes = STEPReaderModes(color: true, name: true, layer: false, props: false)
            if let stepDoc = Document.loadSTEP(fromPath: tmpStep, modes: modes) {
                let roots = stepDoc.rootNodes
                descriptions.append("STEP doc import: \(roots.count) roots (color+name only)")
            }

            try? FileManager.default.removeItem(atPath: tmpStep)
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: descriptions.joined(separator: "\n")
        )
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
