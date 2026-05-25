// Curve2DGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift Curve2D features as colored wireframe bodies on the ground plane.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in 2D curve gallery that renders OCCTSwift Curve2D instances
/// as colored wireframe bodies projected onto the XZ ground plane (Y=0).
enum Curve2DGallery {

    struct GalleryResult {
        var bodies: [ViewportBody]
        var description: String
    }

    // MARK: - Curve Showcase

    /// Circle, arc, ellipse, B-spline, Bezier, and parabola arc — each a different color.
    static func curveShowcase() -> GalleryResult {
        var bodies: [ViewportBody] = []

        // Circle (blue)
        if let circle = Curve2D.circle(center: SIMD2(0, 0), radius: 2.0) {
            bodies.append(curveToBody(circle, id: "curve-circle",
                                      color: SIMD4(0.2, 0.4, 1.0, 1.0)))
        }

        // Arc (cyan)
        if let arc = Curve2D.arcOfCircle(center: SIMD2(5, 0), radius: 1.5,
                                         startAngle: 0, endAngle: .pi * 1.5) {
            bodies.append(curveToBody(arc, id: "curve-arc",
                                      color: SIMD4(0.0, 0.8, 0.9, 1.0)))
        }

        // Ellipse (magenta)
        if let ellipse = Curve2D.ellipse(center: SIMD2(-5, 0),
                                         majorRadius: 2.5, minorRadius: 1.0) {
            bodies.append(curveToBody(ellipse, id: "curve-ellipse",
                                      color: SIMD4(0.9, 0.2, 0.8, 1.0)))
        }

        // B-spline through points (orange)
        if let bspline = Curve2D.interpolate(through: [
            SIMD2(0, 4), SIMD2(1.5, 5.5), SIMD2(3, 4.5),
            SIMD2(4.5, 6), SIMD2(6, 4), SIMD2(7.5, 5)
        ]) {
            bodies.append(curveToBody(bspline, id: "curve-bspline",
                                      color: SIMD4(1.0, 0.6, 0.1, 1.0)))
        }

        // Bezier (green)
        if let bezier = Curve2D.bezier(poles: [
            SIMD2(-6, 4), SIMD2(-4, 8), SIMD2(-1, 3), SIMD2(1, 7)
        ]) {
            bodies.append(curveToBody(bezier, id: "curve-bezier",
                                      color: SIMD4(0.2, 0.9, 0.3, 1.0)))
        }

        // Parabola arc (red)
        if let parabola = Curve2D.arcOfParabola(
            focus: SIMD2(0, -4), direction: SIMD2(0, 1),
            focalLength: 1.0, startParam: -3.0, endParam: 3.0
        ) {
            bodies.append(curveToBody(parabola, id: "curve-parabola",
                                      color: SIMD4(1.0, 0.2, 0.2, 1.0)))
        }

        return GalleryResult(
            bodies: bodies,
            description: "Curve showcase: circle, arc, ellipse, B-spline, Bezier, parabola"
        )
    }

    // MARK: - Intersection Demo

    /// Two curves with small spheres at intersection points.
    static func intersectionDemo() -> GalleryResult {
        var bodies: [ViewportBody] = []

        // Circle
        guard let circle = Curve2D.circle(center: SIMD2(0, 0), radius: 2.0) else {
            return GalleryResult(bodies: [], description: "Failed to create circle")
        }
        bodies.append(curveToBody(circle, id: "intersect-circle",
                                  color: SIMD4(0.2, 0.4, 1.0, 1.0)))

        // Line segment crossing the circle
        guard let segment = Curve2D.segment(from: SIMD2(-4, -1), to: SIMD2(4, 1)) else {
            return GalleryResult(bodies: bodies, description: "Failed to create segment")
        }
        bodies.append(curveToBody(segment, id: "intersect-line",
                                  color: SIMD4(0.9, 0.9, 0.2, 1.0)))

        // Find intersections
        let intersections = circle.intersections(with: segment)
        for (i, ix) in intersections.enumerated() {
            let pos = SIMD3<Float>(Float(ix.point.x), 0, Float(ix.point.y))
            let sphere = makeMarkerSphere(at: pos, radius: 0.12,
                                          id: "intersect-pt-\(i)",
                                          color: SIMD4(1.0, 0.5, 0.0, 1.0))
            bodies.append(sphere)
        }

        // Second pair: ellipse + another line
        if let ellipse = Curve2D.ellipse(center: SIMD2(6, 0),
                                         majorRadius: 3.0, minorRadius: 1.5) {
            bodies.append(curveToBody(ellipse, id: "intersect-ellipse",
                                      color: SIMD4(0.9, 0.2, 0.8, 1.0)))

            if let line2 = Curve2D.segment(from: SIMD2(3, -2), to: SIMD2(9, 2)) {
                bodies.append(curveToBody(line2, id: "intersect-line2",
                                          color: SIMD4(0.9, 0.9, 0.2, 1.0)))

                let ix2 = ellipse.intersections(with: line2)
                for (i, ix) in ix2.enumerated() {
                    let pos = SIMD3<Float>(Float(ix.point.x), 0, Float(ix.point.y))
                    let sphere = makeMarkerSphere(at: pos, radius: 0.12,
                                                  id: "intersect-pt2-\(i)",
                                                  color: SIMD4(1.0, 0.5, 0.0, 1.0))
                    bodies.append(sphere)
                }
            }
        }

        return GalleryResult(
            bodies: bodies,
            description: "Intersections: circle+line and ellipse+line with orange markers at intersection points"
        )
    }

    // MARK: - Hatching Demo

    /// Closed rectangle boundary with parallel hatching fill lines.
    static func hatchingDemo() -> GalleryResult {
        var bodies: [ViewportBody] = []

        // Rectangle corners
        let bl = SIMD2<Double>(-3, -2)
        let br = SIMD2<Double>(3, -2)
        let tr = SIMD2<Double>(3, 2)
        let tl = SIMD2<Double>(-3, 2)

        // Build boundary as 4 line segments
        guard let s1 = Curve2D.segment(from: bl, to: br),
              let s2 = Curve2D.segment(from: br, to: tr),
              let s3 = Curve2D.segment(from: tr, to: tl),
              let s4 = Curve2D.segment(from: tl, to: bl) else {
            return GalleryResult(bodies: [], description: "Failed to create boundary")
        }

        // Render the boundary rectangle
        let boundaryPolyline: [SIMD3<Float>] = [bl, br, tr, tl, bl].map {
            SIMD3<Float>(Float($0.x), 0, Float($0.y))
        }
        bodies.append(ViewportBody(
            id: "hatch-boundary",
            vertexData: [],
            indices: [],
            edges: [boundaryPolyline],
            color: SIMD4(0.2, 0.4, 1.0, 1.0)
        ))

        // Generate hatching at 45 degrees
        let hatchSegments = Curve2DGcc.hatch(
            boundaries: [s1, s2, s3, s4],
            origin: .zero,
            direction: SIMD2(1, 1),
            spacing: 0.4
        )

        // Each hatch segment becomes an edge polyline
        var hatchEdges: [[SIMD3<Float>]] = []
        for seg in hatchSegments {
            let start = SIMD3<Float>(Float(seg.start.x), 0, Float(seg.start.y))
            let end = SIMD3<Float>(Float(seg.end.x), 0, Float(seg.end.y))
            hatchEdges.append([start, end])
        }

        if !hatchEdges.isEmpty {
            bodies.append(ViewportBody(
                id: "hatch-lines",
                vertexData: [],
                indices: [],
                edges: hatchEdges,
                color: SIMD4(0.6, 0.8, 0.3, 1.0)
            ))
        }

        // Add a second region — a triangle with horizontal hatching
        let t1 = SIMD2<Double>(6, -2)
        let t2 = SIMD2<Double>(10, -2)
        let t3 = SIMD2<Double>(8, 2)

        if let ts1 = Curve2D.segment(from: t1, to: t2),
           let ts2 = Curve2D.segment(from: t2, to: t3),
           let ts3 = Curve2D.segment(from: t3, to: t1) {

            let triPolyline: [SIMD3<Float>] = [t1, t2, t3, t1].map {
                SIMD3<Float>(Float($0.x), 0, Float($0.y))
            }
            bodies.append(ViewportBody(
                id: "hatch-triangle-boundary",
                vertexData: [],
                indices: [],
                edges: [triPolyline],
                color: SIMD4(0.9, 0.3, 0.3, 1.0)
            ))

            let triHatch = Curve2DGcc.hatch(
                boundaries: [ts1, ts2, ts3],
                origin: .zero,
                direction: SIMD2(1, 0),
                spacing: 0.3
            )

            var triEdges: [[SIMD3<Float>]] = []
            for seg in triHatch {
                let start = SIMD3<Float>(Float(seg.start.x), 0, Float(seg.start.y))
                let end = SIMD3<Float>(Float(seg.end.x), 0, Float(seg.end.y))
                triEdges.append([start, end])
            }

            if !triEdges.isEmpty {
                bodies.append(ViewportBody(
                    id: "hatch-triangle-lines",
                    vertexData: [],
                    indices: [],
                    edges: triEdges,
                    color: SIMD4(1.0, 0.6, 0.4, 1.0)
                ))
            }
        }

        return GalleryResult(
            bodies: bodies,
            description: "Hatching: rectangle with 45° fill, triangle with horizontal fill"
        )
    }

    // MARK: - Gcc Demo (Tangent Circles)

    /// Two source circles with tangent circle solutions rendered in different colors.
    static func gccDemo() -> GalleryResult {
        var bodies: [ViewportBody] = []

        // Source circle 1
        guard let c1 = Curve2D.circle(center: SIMD2(-2, 0), radius: 1.5) else {
            return GalleryResult(bodies: [], description: "Failed to create source circle 1")
        }
        bodies.append(curveToBody(c1, id: "gcc-source1",
                                  color: SIMD4(0.2, 0.4, 1.0, 1.0)))

        // Source circle 2
        guard let c2 = Curve2D.circle(center: SIMD2(2, 0), radius: 1.0) else {
            return GalleryResult(bodies: bodies, description: "Failed to create source circle 2")
        }
        bodies.append(curveToBody(c2, id: "gcc-source2",
                                  color: SIMD4(0.2, 0.4, 1.0, 1.0)))

        // A point the tangent circle must pass through
        let throughPoint = SIMD2<Double>(0, 3)
        let ptPos = SIMD3<Float>(Float(throughPoint.x), 0, Float(throughPoint.y))
        bodies.append(makeMarkerSphere(at: ptPos, radius: 0.1,
                                       id: "gcc-point",
                                       color: SIMD4(1.0, 1.0, 0.0, 1.0)))

        // Find tangent circles: tangent to both source circles and passing through the point
        let solutions = Curve2DGcc.circlesTangentToTwoCurvesAndPoint(
            c1, .unqualified,
            c2, .unqualified,
            point: throughPoint
        )

        let solutionColors: [SIMD4<Float>] = [
            SIMD4(1.0, 0.3, 0.3, 1.0),  // red
            SIMD4(0.3, 0.9, 0.3, 1.0),  // green
            SIMD4(0.9, 0.6, 0.1, 1.0),  // orange
            SIMD4(0.8, 0.3, 0.9, 1.0),  // purple
        ]

        for (i, sol) in solutions.enumerated() {
            if let solCircle = Curve2D.circle(center: sol.center, radius: sol.radius) {
                let color = solutionColors[i % solutionColors.count]
                bodies.append(curveToBody(solCircle, id: "gcc-solution-\(i)", color: color))
            }
        }

        // Also show tangent lines between the two circles
        let tangentLines = Curve2DGcc.linesTangentTo(c1, .unqualified, c2, .unqualified)
        for (i, line) in tangentLines.enumerated() {
            // Render tangent line as a finite segment
            let p1 = line.point
            let dir = line.direction
            let len = 8.0
            let start = SIMD2(p1.x - dir.x * len, p1.y - dir.y * len)
            let end = SIMD2(p1.x + dir.x * len, p1.y + dir.y * len)
            let s3 = SIMD3<Float>(Float(start.x), 0, Float(start.y))
            let e3 = SIMD3<Float>(Float(end.x), 0, Float(end.y))
            bodies.append(ViewportBody(
                id: "gcc-tangent-line-\(i)",
                vertexData: [],
                indices: [],
                edges: [[s3, e3]],
                color: SIMD4(0.5, 0.5, 0.5, 0.6)
            ))
        }

        let desc = "Gcc: \(solutions.count) tangent circle(s) + \(tangentLines.count) tangent line(s)"
        return GalleryResult(bodies: bodies, description: desc)
    }

    // MARK: - Helpers

    /// Converts a Curve2D to a ViewportBody by projecting onto the XZ ground plane.
    private static func curveToBody(
        _ curve: Curve2D,
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        let points2D = curve.drawAdaptive()
        let polyline: [SIMD3<Float>] = points2D.map {
            SIMD3<Float>(Float($0.x), 0, Float($0.y))
        }
        return ViewportBody(
            id: id,
            vertexData: [],
            indices: [],
            edges: [polyline],
            color: color
        )
    }

    /// Creates a small sphere marker at a given 3D position.
    private static func makeMarkerSphere(
        at position: SIMD3<Float>,
        radius: Float,
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        var sphere = ViewportBody.sphere(
            id: id,
            radius: radius,
            segments: 12,
            rings: 8,
            color: color
        )
        // Offset to position
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
