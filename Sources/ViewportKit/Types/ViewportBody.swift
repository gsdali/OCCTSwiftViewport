// ViewportBody.swift
// ViewportKit
//
// Geometry-source-agnostic input type for Metal rendering.

import simd

/// A renderable body for the Metal viewport.
///
/// Contains interleaved vertex data, triangle indices, and edge polylines
/// for shaded and wireframe rendering.
public struct ViewportBody: Identifiable, Sendable {

    /// Unique identifier for this body.
    public var id: String

    /// Interleaved vertex data: [px, py, pz, nx, ny, nz, ...] with stride 6.
    public var vertexData: [Float]

    /// Triangle indices for shaded rendering.
    public var indices: [UInt32]

    /// Polylines for wireframe rendering. Each inner array is a connected polyline.
    public var edges: [[SIMD3<Float>]]

    /// Body colour (RGBA).
    public var color: SIMD4<Float>

    /// Whether this body should be rendered.
    public var isVisible: Bool

    public init(
        id: String,
        vertexData: [Float],
        indices: [UInt32],
        edges: [[SIMD3<Float>]],
        color: SIMD4<Float>,
        isVisible: Bool = true
    ) {
        self.id = id
        self.vertexData = vertexData
        self.indices = indices
        self.edges = edges
        self.color = color
        self.isVisible = isVisible
    }
}
