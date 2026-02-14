// STEPLoader.swift
// OCCTSwiftMetalDemo
//
// Bridges OCCTSwift geometry to ViewportBody + metadata for sub-body selection.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport

/// Metadata extracted from OCCTSwift for sub-body selection (face, edge, vertex).
struct CADBodyMetadata: Sendable {
    /// Per-triangle face index (parallel to ViewportBody.faceIndices).
    let faceIndices: [Int32]

    /// Edge polylines with their edge indices for edge selection.
    let edgePolylines: [(edgeIndex: Int, points: [SIMD3<Float>])]

    /// Deduplicated edge endpoint vertices for vertex selection.
    let vertices: [SIMD3<Float>]
}

/// Result of loading a STEP file.
struct STEPLoadResult: Sendable {
    var bodies: [ViewportBody]
    var metadata: [String: CADBodyMetadata]
}

/// Loads STEP files via OCCTSwift and converts to ViewportBody arrays.
enum STEPLoader {

    /// Loads a STEP file and returns viewport bodies with selection metadata.
    ///
    /// Runs mesh extraction on a background thread to avoid blocking the main actor.
    static func load(from url: URL) async throws -> STEPLoadResult {
        try await Task.detached {
            try loadSync(from: url)
        }.value
    }

    private static func loadSync(from url: URL) throws -> STEPLoadResult {
        let doc = try Document.load(from: url)
        let shapesWithColors = doc.shapesWithColors()

        var bodies: [ViewportBody] = []
        var metadata: [String: CADBodyMetadata] = [:]

        for (index, pair) in shapesWithColors.enumerated() {
            let shape = pair.shape
            let color = pair.color

            let bodyID = "step-\(index)"

            // Convert color
            let rgba: SIMD4<Float>
            if let c = color {
                rgba = SIMD4<Float>(Float(c.red), Float(c.green), Float(c.blue), Float(c.alpha))
            } else {
                rgba = SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
            }

            // Extract mesh with face indices
            guard let mesh = shape.mesh(linearDeflection: 0.1) else {
                // Edge-only body — try to get edge polylines
                let edgePolylines = extractEdgePolylines(from: shape)
                if !edgePolylines.isEmpty {
                    let edges = edgePolylines.map { $0.points }
                    let verts = deduplicateVertices(from: edgePolylines)
                    let body = ViewportBody(
                        id: bodyID,
                        vertexData: [],
                        indices: [],
                        edges: edges,
                        color: rgba
                    )
                    bodies.append(body)
                    metadata[bodyID] = CADBodyMetadata(
                        faceIndices: [],
                        edgePolylines: edgePolylines,
                        vertices: verts
                    )
                }
                continue
            }

            // Interleave vertices and normals into stride-6 format
            let vertexCount = mesh.vertexCount
            var vertexData: [Float] = []
            vertexData.reserveCapacity(vertexCount * 6)
            let positions = mesh.vertices
            let normals = mesh.normals
            for i in 0..<vertexCount {
                let p = positions[i]
                let n = normals[i]
                vertexData.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z])
            }

            // Extract face indices from trianglesWithFaces
            let triangles = mesh.trianglesWithFaces()
            var faceIndices: [Int32] = []
            faceIndices.reserveCapacity(triangles.count)
            for tri in triangles {
                faceIndices.append(tri.faceIndex)
            }

            // Use mesh indices directly
            let indices = mesh.indices

            // Extract edge polylines
            let edgePolylines = extractEdgePolylines(from: shape)
            let edges = edgePolylines.map { $0.points }

            // Deduplicate edge endpoint vertices
            let uniqueVerts = deduplicateVertices(from: edgePolylines)

            let body = ViewportBody(
                id: bodyID,
                vertexData: vertexData,
                indices: indices,
                edges: edges,
                faceIndices: faceIndices,
                color: rgba
            )
            bodies.append(body)

            metadata[bodyID] = CADBodyMetadata(
                faceIndices: faceIndices,
                edgePolylines: edgePolylines,
                vertices: uniqueVerts
            )
        }

        return STEPLoadResult(bodies: bodies, metadata: metadata)
    }

    // MARK: - Edge Extraction

    private static func extractEdgePolylines(
        from shape: Shape
    ) -> [(edgeIndex: Int, points: [SIMD3<Float>])] {
        let count = shape.edgeCount
        var result: [(edgeIndex: Int, points: [SIMD3<Float>])] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            guard let polyline = shape.edgePolyline(at: i, deflection: 0.1) else { continue }
            let floatPoints = polyline.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            guard floatPoints.count >= 2 else { continue }
            result.append((edgeIndex: i, points: floatPoints))
        }

        return result
    }

    // MARK: - Vertex Deduplication

    private static func deduplicateVertices(
        from edgePolylines: [(edgeIndex: Int, points: [SIMD3<Float>])]
    ) -> [SIMD3<Float>] {
        let tolerance: Float = 1e-5
        var unique: [SIMD3<Float>] = []

        for polyline in edgePolylines {
            guard let first = polyline.points.first, let last = polyline.points.last else { continue }
            for endpoint in [first, last] {
                let isDuplicate = unique.contains { existing in
                    simd_distance(existing, endpoint) < tolerance
                }
                if !isDuplicate {
                    unique.append(endpoint)
                }
            }
        }

        return unique
    }
}
