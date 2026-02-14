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

    // Auto-incrementing generation counter for cache invalidation.
    private nonisolated(unsafe) static var _nextGeneration: UInt64 = 0

    /// Unique identifier for this body.
    public var id: String

    /// Generation tag — each `ViewportBody.init` gets a unique value.
    /// Used by the renderer to detect geometry changes.
    public let generation: UInt64

    /// Interleaved vertex data: [px, py, pz, nx, ny, nz, ...] with stride 6.
    public var vertexData: [Float]

    /// Triangle indices for shaded rendering.
    public var indices: [UInt32]

    /// Polylines for wireframe rendering. Each inner array is a connected polyline.
    public var edges: [[SIMD3<Float>]]

    /// Per-triangle source face index. Parallel to triangle count (`indices.count / 3`).
    /// Maps each triangle back to its B-Rep face for sub-body selection. Empty if not applicable.
    public var faceIndices: [Int32]

    /// Body colour (RGBA).
    public var color: SIMD4<Float>

    /// Whether this body should be rendered.
    public var isVisible: Bool

    public init(
        id: String,
        vertexData: [Float],
        indices: [UInt32],
        edges: [[SIMD3<Float>]],
        faceIndices: [Int32] = [],
        color: SIMD4<Float>,
        isVisible: Bool = true
    ) {
        ViewportBody._nextGeneration += 1
        self.generation = ViewportBody._nextGeneration
        self.id = id
        self.vertexData = vertexData
        self.indices = indices
        self.edges = edges
        self.faceIndices = faceIndices
        self.color = color
        self.isVisible = isVisible
    }
}

// MARK: - Bounding Box

extension ViewportBody {

    /// Computes the axis-aligned bounding box from vertex positions.
    ///
    /// Returns `nil` if the body has no vertex data.
    public var boundingBox: BoundingBox? {
        let stride = 6
        let vertexCount = vertexData.count / stride
        guard vertexCount > 0 else { return nil }

        var bbMin = SIMD3<Float>(vertexData[0], vertexData[1], vertexData[2])
        var bbMax = bbMin

        for i in 1..<vertexCount {
            let base = i * stride
            let p = SIMD3<Float>(vertexData[base], vertexData[base + 1], vertexData[base + 2])
            bbMin = simd_min(bbMin, p)
            bbMax = simd_max(bbMax, p)
        }

        return BoundingBox(min: bbMin, max: bbMax)
    }
}
