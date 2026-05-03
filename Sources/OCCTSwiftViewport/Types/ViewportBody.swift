// ViewportBody.swift
// ViewportKit
//
// Geometry-source-agnostic input type for Metal rendering.

import simd

/// Render-time layering for a body.
///
/// `.geometry` participates in normal depth testing. `.overlay` is drawn after the
/// selection outline pass with an always-pass depth state, so the body is visible
/// even when occluded by other geometry — used by manipulator widgets and similar
/// always-on-top UI affordances.
public enum RenderLayer: Hashable, Sendable {
    case geometry
    case overlay
}

/// Pick stream a body belongs to.
///
/// `.userGeometry` results land in `ViewportController.pickResult`. `.widget`
/// results land in `ViewportController.widgetPickResult`, so consumers (e.g.,
/// OCCTSwiftAIS manipulators) can run their own pick handling without leaking
/// into the user selection stream.
public enum PickLayer: Hashable, Sendable {
    case userGeometry
    case widget
}

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

    /// Per-line-segment source-edge index. Parallel to the line primitives in
    /// `edges` flattened ([poly0.seg0, poly0.seg1, ..., poly1.seg0, ...]). Maps
    /// a picked edge segment back to its B-Rep edge for selection. Empty if not
    /// applicable — in which case the body is not edge-pickable.
    public var edgeIndices: [Int32]

    /// Optional point list rendered as point sprites in the pick pass for
    /// vertex picking. Each entry is one B-Rep vertex position. Empty if not
    /// applicable — in which case the body is not vertex-pickable.
    public var vertices: [SIMD3<Float>]

    /// Per-point source-vertex index. Parallel to `vertices`. Maps a picked
    /// point back to its B-Rep vertex. Empty defaults to identity (i.e. the
    /// pick result's `primitiveIndex` is the vertex index directly).
    public var vertexIndices: [Int32]

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

    /// Render-time layer. `.overlay` bodies are drawn always-on-top.
    public var renderLayer: RenderLayer

    /// Pick stream this body belongs to. `.widget` results route to
    /// `ViewportController.widgetPickResult` instead of `pickResult`.
    public var pickLayer: PickLayer

    /// Per-body model transform. Applied as an additional matrix on top of the
    /// scene model matrix in the vertex shader, so the renderer can move a body
    /// (e.g., during a manipulator drag) without re-uploading vertex data.
    public var transform: simd_float4x4

    public init(
        id: String,
        vertexData: [Float],
        indices: [UInt32],
        edges: [[SIMD3<Float>]],
        faceIndices: [Int32] = [],
        edgeIndices: [Int32] = [],
        vertices: [SIMD3<Float>] = [],
        vertexIndices: [Int32] = [],
        color: SIMD4<Float>,
        roughness: Float = 0.5,
        metallic: Float = 0.0,
        material: PBRMaterial? = nil,
        isVisible: Bool = true,
        renderLayer: RenderLayer = .geometry,
        pickLayer: PickLayer = .userGeometry,
        transform: simd_float4x4 = matrix_identity_float4x4
    ) {
        ViewportBody._nextGeneration += 1
        self.generation = ViewportBody._nextGeneration
        self.id = id
        self.vertexData = vertexData
        self.indices = indices
        self.edges = edges
        self.faceIndices = faceIndices
        self.edgeIndices = edgeIndices
        self.vertices = vertices
        self.vertexIndices = vertexIndices
        self.color = color
        self.roughness = roughness
        self.metallic = metallic
        self.material = material
        self.isVisible = isVisible
        self.renderLayer = renderLayer
        self.pickLayer = pickLayer
        self.transform = transform
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
