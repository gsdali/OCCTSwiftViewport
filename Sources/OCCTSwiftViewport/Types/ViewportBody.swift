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

    /// Body colour (RGBA). Used as the base colour fallback when `material` is nil.
    public var color: SIMD4<Float>

    /// Surface roughness (0 = mirror, 1 = fully rough). Default 0.5.
    /// Ignored when `material` is set.
    public var roughness: Float

    /// Metallic factor (0 = dielectric, 1 = metal). Default 0.0.
    /// Ignored when `material` is set.
    public var metallic: Float

    /// Optional full PBR material. When set, overrides `color`/`roughness`/`metallic`
    /// and enables clearcoat, IOR-driven F0, and emission.
    public var material: PBRMaterial?

    /// Whether this body should be rendered.
    public var isVisible: Bool

    public init(
        id: String,
        vertexData: [Float],
        indices: [UInt32],
        edges: [[SIMD3<Float>]],
        faceIndices: [Int32] = [],
        color: SIMD4<Float>,
        roughness: Float = 0.5,
        metallic: Float = 0.0,
        material: PBRMaterial? = nil,
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
        self.roughness = roughness
        self.metallic = metallic
        self.material = material
        self.isVisible = isVisible
    }
}

// MARK: - Effective material

extension ViewportBody {

    /// Returns `material` if set, otherwise a `PBRMaterial` derived from the
    /// legacy `color`/`roughness`/`metallic` fields. The renderer should call
    /// this rather than reading either source directly.
    public var effectiveMaterial: PBRMaterial {
        if let material { return material }
        return PBRMaterial(
            baseColor: SIMD3<Float>(color.x, color.y, color.z),
            metallic: metallic,
            roughness: roughness,
            opacity: color.w
        )
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
