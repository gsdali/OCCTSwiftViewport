// SweepGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift LawFunction variable-section pipe sweeps.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Built-in variable-section sweep gallery that renders pipe shells
/// where cross-section radius varies according to a law function.
enum SweepGallery {

    // MARK: - Constant Pipe

    /// Uniform pipe along a curved spine (law = constant).
    static func constantPipe() -> Curve2DGallery.GalleryResult {
        guard let result = buildPipeSweep(
            law: .constant(1.0, from: 0, to: 1),
            idPrefix: "sweep-const",
            color: SIMD4(0.3, 0.6, 1.0, 1.0),
            lawColor: SIMD4(0.3, 0.6, 1.0, 1.0)
        ) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create constant pipe")
        }
        return result
    }

    // MARK: - Linear Taper

    /// Tapered pipe that narrows from start to end (law = linear).
    static func linearTaper() -> Curve2DGallery.GalleryResult {
        guard let result = buildPipeSweep(
            law: .linear(from: 1.2, to: 0.3, parameterRange: 0...1),
            idPrefix: "sweep-linear",
            color: SIMD4(0.2, 0.8, 0.4, 1.0),
            lawColor: SIMD4(0.2, 0.8, 0.4, 1.0)
        ) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create linear taper")
        }
        return result
    }

    // MARK: - S-Curve Sweep

    /// Pipe with a smooth bulge in the middle (law = S-curve).
    static func sCurveSweep() -> Curve2DGallery.GalleryResult {
        guard let result = buildPipeSweep(
            law: .sCurve(from: 0.5, to: 1.5, parameterRange: 0...1),
            idPrefix: "sweep-scurve",
            color: SIMD4(0.9, 0.4, 0.2, 1.0),
            lawColor: SIMD4(0.9, 0.4, 0.2, 1.0)
        ) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create S-curve sweep")
        }
        return result
    }

    // MARK: - Interpolated Sweep

    /// Pipe with custom varying cross-section (law = interpolated).
    static func interpolatedSweep() -> Curve2DGallery.GalleryResult {
        guard let result = buildPipeSweep(
            law: .interpolate(points: [
                (parameter: 0.0, value: 0.5),
                (parameter: 0.25, value: 1.2),
                (parameter: 0.5, value: 0.4),
                (parameter: 0.75, value: 1.0),
                (parameter: 1.0, value: 0.6),
            ]),
            idPrefix: "sweep-interp",
            color: SIMD4(0.8, 0.3, 0.9, 1.0),
            lawColor: SIMD4(0.8, 0.3, 0.9, 1.0)
        ) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create interpolated sweep")
        }
        return result
    }

    // MARK: - Helpers

    /// Builds a pipe sweep demo with a common spine, profile, and law function.
    private static func buildPipeSweep(
        law: LawFunction?,
        idPrefix: String,
        color: SIMD4<Float>,
        lawColor: SIMD4<Float>
    ) -> Curve2DGallery.GalleryResult? {
        guard let law else { return nil }

        // Create a curved spine wire
        guard let spineWire = Wire.path([
            SIMD3(0, 0, 0), SIMD3(2, 1, 1), SIMD3(4, 0, 2),
            SIMD3(6, -1, 1), SIMD3(8, 0, 0)
        ]) else { return nil }

        // Create a circular profile wire
        guard let profileWire = Wire.circle(radius: 1.0) else { return nil }

        // Build the pipe shell with law
        guard let pipeShape = Shape.pipeShellWithLaw(
            spine: spineWire, profile: profileWire, law: law
        ) else { return nil }

        // Convert to viewport body
        let (body, _) = CADFileLoader.shapeToBodyAndMetadata(pipeShape, id: idPrefix, color: color)

        var bodies: [ViewportBody] = []
        if let body {
            bodies.append(body)
        }

        // Visualize the law function as a 2D curve in the corner
        bodies.append(contentsOf: lawToBody(law, idPrefix: "\(idPrefix)-law",
                                            color: lawColor, offset: SIMD3(-4, -3, 0)))

        // Show the spine as a wireframe overlay
        bodies.append(spineBody(idPrefix: "\(idPrefix)-spine"))

        return Curve2DGallery.GalleryResult(
            bodies: bodies,
            description: "\(idPrefix): variable-section pipe shell"
        )
    }

    /// Renders a LawFunction as a 2D plot on the XZ plane at the given offset.
    private static func lawToBody(
        _ law: LawFunction,
        idPrefix: String,
        color: SIMD4<Float>,
        offset: SIMD3<Float>
    ) -> [ViewportBody] {
        let bounds = law.bounds
        let sampleCount = 50
        let dt = (bounds.upperBound - bounds.lowerBound) / Double(sampleCount)
        let xScale: Float = 3.0  // visual width of the plot
        let yScale: Float = 2.0  // visual height of the plot

        var polyline: [SIMD3<Float>] = []
        for i in 0...sampleCount {
            let t = bounds.lowerBound + Double(i) * dt
            let v = law.value(at: t)
            let x = Float(Double(i) / Double(sampleCount)) * xScale + offset.x
            let y = Float(v) * yScale + offset.y
            let z = offset.z
            polyline.append(SIMD3(x, y, z))
        }

        var bodies: [ViewportBody] = []

        // The law curve
        bodies.append(ViewportBody(
            id: idPrefix,
            vertexData: [],
            indices: [],
            edges: [polyline],
            color: color
        ))

        // Baseline (gray)
        let baseline: [SIMD3<Float>] = [
            SIMD3(offset.x, offset.y, offset.z),
            SIMD3(offset.x + xScale, offset.y, offset.z)
        ]
        bodies.append(ViewportBody(
            id: "\(idPrefix)-base",
            vertexData: [],
            indices: [],
            edges: [baseline],
            color: SIMD4(0.4, 0.4, 0.4, 0.5)
        ))

        return bodies
    }

    /// Creates a wireframe spine body for reference.
    private static func spineBody(idPrefix: String) -> ViewportBody {
        let spinePoints: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(2, 1, 1), SIMD3(4, 0, 2),
            SIMD3(6, -1, 1), SIMD3(8, 0, 0)
        ]
        return ViewportBody(
            id: idPrefix,
            vertexData: [],
            indices: [],
            edges: [spinePoints],
            color: SIMD4(1.0, 1.0, 0.0, 0.6)
        )
    }
}
