// Curve3DGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift Curve3D features as colored wireframe bodies in 3D space.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in 3D curve gallery that renders OCCTSwift Curve3D instances
/// as colored wireframe bodies in 3D space.
enum Curve3DGallery {

    // MARK: - Curve Showcase

    /// Line, circle, arc, ellipse, B-spline, and Bezier in 3D space, each a different color.
    static func curveShowcase() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Line segment (white)
        if let line = Curve3D.segment(
            from: SIMD3(-3, 0, 0),
            to: SIMD3(3, 0, 0)
        ) {
            bodies.append(curveToBody(line, id: "c3d-line",
                                      color: SIMD4(0.9, 0.9, 0.9, 1.0)))
        }

        // Circle (blue) — in the XY plane at Z=2
        if let circle = Curve3D.circle(
            center: SIMD3(0, 0, 2),
            normal: SIMD3(0, 0, 1),
            radius: 2.0
        ) {
            bodies.append(curveToBody(circle, id: "c3d-circle",
                                      color: SIMD4(0.2, 0.4, 1.0, 1.0)))
        }

        // Arc through 3 points (cyan)
        if let arc = Curve3D.arc(
            through: SIMD3(-2, 0, 4),
            SIMD3(0, 1.5, 5),
            SIMD3(2, 0, 4)
        ) {
            bodies.append(curveToBody(arc, id: "c3d-arc",
                                      color: SIMD4(0.0, 0.8, 0.9, 1.0)))
        }

        // Ellipse (magenta) — tilted plane
        if let ellipse = Curve3D.ellipse(
            center: SIMD3(5, 0, 2),
            normal: SIMD3(0, 1, 1),
            majorRadius: 2.0,
            minorRadius: 1.0
        ) {
            bodies.append(curveToBody(ellipse, id: "c3d-ellipse",
                                      color: SIMD4(0.9, 0.2, 0.8, 1.0)))
        }

        // BSpline through 3D points (orange)
        if let bspline = Curve3D.interpolate(points: [
            SIMD3(-4, 0, 6), SIMD3(-2, 2, 7), SIMD3(0, 0, 8),
            SIMD3(2, -1, 7), SIMD3(4, 1, 6)
        ]) {
            bodies.append(curveToBody(bspline, id: "c3d-bspline",
                                      color: SIMD4(1.0, 0.6, 0.1, 1.0)))
        }

        // Bezier (green)
        if let bezier = Curve3D.bezier(poles: [
            SIMD3(-3, 2, 0), SIMD3(-1, 4, 2), SIMD3(1, 0, 4), SIMD3(3, 3, 2)
        ]) {
            bodies.append(curveToBody(bezier, id: "c3d-bezier",
                                      color: SIMD4(0.2, 0.9, 0.3, 1.0)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "3D Curve showcase: line, circle, arc, ellipse, B-spline, Bezier"
        )
    }

    // MARK: - Helix & Spirals

    /// Helix, conical spiral, reversed curve, and trimmed curve.
    static func helixAndSpirals() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Generate helical points
        let helixPoints: [SIMD3<Double>] = (0...60).map { i in
            let t = Double(i) / 60.0 * 4.0 * .pi
            return SIMD3(2.0 * cos(t), 2.0 * sin(t), t / .pi)
        }

        if let helix = Curve3D.interpolate(points: helixPoints) {
            bodies.append(curveToBody(helix, id: "c3d-helix",
                                      color: SIMD4(0.2, 0.6, 1.0, 1.0)))

            // Reversed helix (red), offset to the right
            if let reversed = helix.reversed()?.translated(by: SIMD3(6, 0, 0)) {
                bodies.append(curveToBody(reversed, id: "c3d-helix-rev",
                                          color: SIMD4(1.0, 0.3, 0.3, 1.0)))
            }

            // Trimmed helix — first quarter (yellow)
            let domain = helix.domain
            let trimEnd = domain.lowerBound + (domain.upperBound - domain.lowerBound) * 0.25
            if let trimmed = helix.trimmed(from: domain.lowerBound, to: trimEnd)?
                .translated(by: SIMD3(-6, 0, 0)) {
                bodies.append(curveToBody(trimmed, id: "c3d-helix-trim",
                                          color: SIMD4(1.0, 1.0, 0.2, 1.0)))
            }
        }

        // Conical spiral — increasing radius
        let spiralPoints: [SIMD3<Double>] = (0...50).map { i in
            let t = Double(i) / 50.0 * 3.0 * .pi
            let r = 0.5 + t / (3.0 * .pi) * 2.5
            return SIMD3(r * cos(t), r * sin(t), t / .pi + 6)
        }

        if let spiral = Curve3D.interpolate(points: spiralPoints) {
            bodies.append(curveToBody(spiral, id: "c3d-spiral",
                                      color: SIMD4(0.9, 0.5, 1.0, 1.0)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Helix & spirals: helix (blue), reversed (red), trimmed (yellow), conical spiral (purple)"
        )
    }

    // MARK: - Curvature Combs

    /// A BSpline curve with curvature combs rendered as perpendicular line segments.
    static func curvatureCombs() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Create a wavy BSpline in 3D
        guard let curve = Curve3D.interpolate(points: [
            SIMD3(-4, 0, 0), SIMD3(-2, 2, 1), SIMD3(0, -1, 2),
            SIMD3(2, 3, 1), SIMD3(4, 0, 0)
        ]) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create curve")
        }

        // Render the curve itself (white)
        bodies.append(curveToBody(curve, id: "c3d-comb-curve",
                                  color: SIMD4(0.9, 0.9, 0.9, 1.0)))

        // Sample curvature at N points to build comb teeth
        let sampleCount = 40
        let domain = curve.domain
        let dt = (domain.upperBound - domain.lowerBound) / Double(sampleCount)
        let combScale = 2.0 // visual scale for comb teeth

        var combEdges: [[SIMD3<Float>]] = []

        for i in 0...sampleCount {
            let t = domain.lowerBound + Double(i) * dt
            let p = curve.point(at: t)
            let k = curve.curvature(at: t)

            guard let normal = curve.normal(at: t) else { continue }

            // Comb tooth: line from curve point along normal, length = curvature * scale
            let toothLength = k * combScale
            let end = p + normal * toothLength

            let pf = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            let ef = SIMD3<Float>(Float(end.x), Float(end.y), Float(end.z))
            combEdges.append([pf, ef])
        }

        // Connect comb tips for a smooth envelope
        var tipPoints: [SIMD3<Float>] = []
        for i in 0...sampleCount {
            let t = domain.lowerBound + Double(i) * dt
            let p = curve.point(at: t)
            let k = curve.curvature(at: t)
            if let normal = curve.normal(at: t) {
                let end = p + normal * (k * combScale)
                tipPoints.append(SIMD3<Float>(Float(end.x), Float(end.y), Float(end.z)))
            }
        }

        if !combEdges.isEmpty {
            bodies.append(ViewportBody(
                id: "c3d-comb-teeth",
                vertexData: [],
                indices: [],
                edges: combEdges,
                color: SIMD4(0.0, 0.8, 0.4, 1.0)
            ))
        }

        if tipPoints.count >= 2 {
            bodies.append(ViewportBody(
                id: "c3d-comb-envelope",
                vertexData: [],
                indices: [],
                edges: [tipPoints],
                color: SIMD4(1.0, 0.4, 0.1, 1.0)
            ))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "Curvature combs: curve (white), teeth (green), envelope (orange)"
        )
    }

    // MARK: - BSpline Fitting

    /// Fits a BSpline through noisy sample points, showing both the points and fitted curve.
    static func bsplineFitting() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []

        // Generate points along a known curve with noise
        let pointCount = 25
        var samplePoints: [SIMD3<Double>] = []
        for i in 0..<pointCount {
            let t = Double(i) / Double(pointCount - 1) * 2.0 * .pi
            let x = 3.0 * cos(t) + Double.random(in: -0.15...0.15)
            let y = 2.0 * sin(t) + Double.random(in: -0.15...0.15)
            let z = t / .pi + Double.random(in: -0.1...0.1)
            samplePoints.append(SIMD3(x, y, z))
        }

        // Render sample points as small spheres (yellow)
        for (i, pt) in samplePoints.enumerated() {
            let pos = SIMD3<Float>(Float(pt.x), Float(pt.y), Float(pt.z))
            let sphere = makeMarkerSphere(at: pos, radius: 0.08,
                                          id: "c3d-fit-pt-\(i)",
                                          color: SIMD4(1.0, 0.9, 0.2, 1.0))
            bodies.append(sphere)
        }

        // Fit a BSpline through the points
        if let fitted = Curve3D.fit(points: samplePoints, tolerance: 0.2) {
            bodies.append(curveToBody(fitted, id: "c3d-fitted",
                                      color: SIMD4(0.2, 0.6, 1.0, 1.0)))
        }

        // Also show an exact interpolation for comparison (green)
        if let exact = Curve3D.interpolate(points: samplePoints) {
            bodies.append(curveToBody(exact, id: "c3d-interp",
                                      color: SIMD4(0.3, 0.9, 0.3, 0.5)))
        }

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "BSpline fitting: noisy points (yellow), fitted curve (blue), interpolated (green)"
        )
    }

    // MARK: - Helpers

    /// Converts a Curve3D to a ViewportBody using adaptive tessellation.
    private static func curveToBody(
        _ curve: Curve3D,
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        let points3D = curve.drawAdaptive()
        let polyline: [SIMD3<Float>] = points3D.map {
            SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
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
            segments: 10,
            rings: 6,
            color: color
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
