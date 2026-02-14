// SelectionManager.swift
// OCCTSwiftMetalDemo
//
// Manages sub-body selection (face, edge, vertex) and produces highlight overlays.

import Foundation
import simd
import OCCTSwiftViewport

/// Manages selection state and produces highlight overlay bodies.
@MainActor
final class SelectionManager: ObservableObject {

    /// Current selection mode.
    @Published var mode: SelectionMode = .body

    /// Highlight overlay bodies to add to the scene.
    @Published private(set) var highlightBodies: [ViewportBody] = []

    /// Human-readable description of the current selection.
    @Published private(set) var selectionInfo: String = ""

    /// Clears all selection state.
    func clearSelection() {
        highlightBodies = []
        selectionInfo = ""
    }

    // MARK: - Handle Pick

    /// Processes a pick result and generates highlight overlays.
    func handlePick(
        result: PickResult?,
        ndc: SIMD2<Float>,
        bodies: [ViewportBody],
        metadata: [String: CADBodyMetadata],
        cameraState: CameraState,
        aspectRatio: Float
    ) {
        highlightBodies = []
        selectionInfo = ""

        guard let result = result else { return }
        guard let body = bodies.first(where: { $0.id == result.bodyID }) else { return }

        switch mode {
        case .body:
            handleBodySelection(result: result, body: body)
        case .face:
            handleFaceSelection(result: result, body: body, metadata: metadata)
        case .edge:
            handleEdgeSelection(
                result: result, body: body, metadata: metadata,
                ndc: ndc, cameraState: cameraState, aspectRatio: aspectRatio
            )
        case .vertex:
            handleVertexSelection(
                result: result, body: body, metadata: metadata,
                ndc: ndc, cameraState: cameraState, aspectRatio: aspectRatio
            )
        }
    }

    // MARK: - Body Selection

    private func handleBodySelection(result: PickResult, body: ViewportBody) {
        selectionInfo = "Body: \(result.bodyID)"
        // Body selection is handled by the caller (color brightening)
    }

    // MARK: - Face Selection

    private func handleFaceSelection(
        result: PickResult,
        body: ViewportBody,
        metadata: [String: CADBodyMetadata]
    ) {
        guard let meta = metadata[result.bodyID] else {
            // No metadata — fall back to body selection info
            selectionInfo = "Face: (no metadata for \(result.bodyID))"
            return
        }

        guard !meta.faceIndices.isEmpty else {
            selectionInfo = "Face: (no face indices)"
            return
        }

        let triIndex = result.triangleIndex
        guard triIndex < meta.faceIndices.count else {
            selectionInfo = "Face: (triangle \(triIndex) out of range)"
            return
        }

        let faceIndex = meta.faceIndices[triIndex]
        selectionInfo = "Face \(faceIndex) on \(result.bodyID)"

        // Collect all triangles belonging to this face
        let stride = 6
        var overlayVerts: [Float] = []
        var overlayIndices: [UInt32] = []
        var vertIdx: UInt32 = 0

        for (ti, fi) in meta.faceIndices.enumerated() {
            guard fi == faceIndex else { continue }
            let baseIndex = ti * 3
            guard baseIndex + 2 < body.indices.count else { continue }

            for j in 0..<3 {
                let srcIdx = Int(body.indices[baseIndex + j])
                let base = srcIdx * stride
                guard base + 5 < body.vertexData.count else { continue }

                // Position + small offset along normal to prevent z-fighting
                let px = body.vertexData[base]
                let py = body.vertexData[base + 1]
                let pz = body.vertexData[base + 2]
                let nx = body.vertexData[base + 3]
                let ny = body.vertexData[base + 4]
                let nz = body.vertexData[base + 5]

                let offset: Float = 0.002
                overlayVerts.append(contentsOf: [
                    px + nx * offset, py + ny * offset, pz + nz * offset,
                    nx, ny, nz
                ])
            }
            overlayIndices.append(contentsOf: [vertIdx, vertIdx + 1, vertIdx + 2])
            vertIdx += 3
        }

        guard !overlayIndices.isEmpty else { return }

        let highlight = ViewportBody(
            id: "highlight-face",
            vertexData: overlayVerts,
            indices: overlayIndices,
            edges: [],
            color: SIMD4<Float>(0.2, 0.5, 1.0, 0.6)
        )
        highlightBodies = [highlight]
    }

    // MARK: - Edge Selection

    private func handleEdgeSelection(
        result: PickResult,
        body: ViewportBody,
        metadata: [String: CADBodyMetadata],
        ndc: SIMD2<Float>,
        cameraState: CameraState,
        aspectRatio: Float
    ) {
        guard let meta = metadata[result.bodyID] else {
            selectionInfo = "Edge: (no metadata for \(result.bodyID))"
            return
        }

        // Get 3D hit point from the picked triangle
        let ray = Ray.fromCamera(ndc: ndc, cameraState: cameraState, aspectRatio: aspectRatio)
        guard let hitPoint = GeometryUtils.hitPointOnTriangle(
            ray: ray, body: body, triangleIndex: result.triangleIndex
        ) else {
            selectionInfo = "Edge: (no hit point)"
            return
        }

        // Find nearest edge polyline
        var bestDist: Float = .infinity
        var bestEdgeIdx = -1
        var bestPolyline: [SIMD3<Float>] = []

        for ep in meta.edgePolylines {
            let dist = GeometryUtils.pointToPolylineDistance(point: hitPoint, polyline: ep.points)
            if dist < bestDist {
                bestDist = dist
                bestEdgeIdx = ep.edgeIndex
                bestPolyline = ep.points
            }
        }

        guard bestEdgeIdx >= 0 else {
            selectionInfo = "Edge: (no edges found)"
            return
        }

        selectionInfo = "Edge \(bestEdgeIdx) on \(result.bodyID) (dist: \(String(format: "%.3f", bestDist)))"

        // Build edge overlay body (edges only, no mesh)
        let highlight = ViewportBody(
            id: "highlight-edge",
            vertexData: [],
            indices: [],
            edges: [bestPolyline],
            color: SIMD4<Float>(0.0, 1.0, 0.3, 1.0)
        )
        highlightBodies = [highlight]
    }

    // MARK: - Vertex Selection

    private func handleVertexSelection(
        result: PickResult,
        body: ViewportBody,
        metadata: [String: CADBodyMetadata],
        ndc: SIMD2<Float>,
        cameraState: CameraState,
        aspectRatio: Float
    ) {
        guard let meta = metadata[result.bodyID] else {
            selectionInfo = "Vertex: (no metadata for \(result.bodyID))"
            return
        }

        guard !meta.vertices.isEmpty else {
            selectionInfo = "Vertex: (no vertices)"
            return
        }

        // Get 3D hit point from the picked triangle
        let ray = Ray.fromCamera(ndc: ndc, cameraState: cameraState, aspectRatio: aspectRatio)
        guard let hitPoint = GeometryUtils.hitPointOnTriangle(
            ray: ray, body: body, triangleIndex: result.triangleIndex
        ) else {
            selectionInfo = "Vertex: (no hit point)"
            return
        }

        // Find nearest vertex
        var bestDist: Float = .infinity
        var bestVertex: SIMD3<Float> = .zero

        for v in meta.vertices {
            let dist = simd_distance(hitPoint, v)
            if dist < bestDist {
                bestDist = dist
                bestVertex = v
            }
        }

        guard bestDist < .infinity else {
            selectionInfo = "Vertex: (no vertex found)"
            return
        }

        selectionInfo = String(format: "Vertex (%.3f, %.3f, %.3f) on %@",
                              bestVertex.x, bestVertex.y, bestVertex.z, result.bodyID)

        // Build a small sphere at the vertex position, radius scaled by camera distance
        let radius = cameraState.distance * 0.008
        var sphere = ViewportBody.sphere(
            id: "highlight-vertex",
            radius: radius,
            segments: 12,
            rings: 8,
            color: SIMD4<Float>(1.0, 0.6, 0.0, 1.0)
        )

        // Offset sphere vertices to the vertex position
        let stride = 6
        var offsetVerts: [Float] = []
        offsetVerts.reserveCapacity(sphere.vertexData.count)
        for i in Swift.stride(from: 0, to: sphere.vertexData.count, by: stride) {
            offsetVerts.append(sphere.vertexData[i] + bestVertex.x)
            offsetVerts.append(sphere.vertexData[i + 1] + bestVertex.y)
            offsetVerts.append(sphere.vertexData[i + 2] + bestVertex.z)
            offsetVerts.append(sphere.vertexData[i + 3])
            offsetVerts.append(sphere.vertexData[i + 4])
            offsetVerts.append(sphere.vertexData[i + 5])
        }
        sphere.vertexData = offsetVerts

        highlightBodies = [sphere]
    }
}
