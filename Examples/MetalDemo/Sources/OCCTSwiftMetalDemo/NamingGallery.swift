// NamingGallery.swift
// OCCTSwiftMetalDemo
//
// Demonstrates OCCTSwift TNaming — topological naming history tracking.
// Shows how shapes can be tracked through modeling operations using persistent naming.

import Foundation
import simd
import OCCTSwift
import OCCTSwiftViewport
import OCCTSwiftTools

/// Built-in gallery demonstrating topological naming history on XDE documents.
/// Each demo creates shapes, records naming evolutions, and visualizes the
/// forward/backward tracing through the naming graph.
enum NamingGallery {

    // MARK: - Primitive Creation History

    /// Creates a box, records it as a primitive, then shows the stored shape.
    static func primitiveHistory() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Primitive naming history"

        // Create a document and a label
        guard let doc = Document.create(),
              let node = doc.createLabel() else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create document")
        }

        // Create a box shape
        guard let box = Shape.box(width: 3, height: 2, depth: 1.5) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create box")
        }

        // Record as primitive (new shape created from scratch)
        let _ = doc.recordNaming(on: node, evolution: .primitive, newShape: box)

        // Query evolution
        let evolution = doc.namingEvolution(on: node)
        info += "\nEvolution: \(evolutionName(evolution))"

        // Retrieve the current shape
        if let current = doc.currentShape(on: node) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                current, id: "naming-prim-current",
                color: SIMD4(0.3, 0.6, 1.0, 1.0)
            )
            if let body { bodies.append(body) }
            info += "\nCurrent shape: retrieved"
        }

        // Retrieve stored shape
        if let stored = doc.storedShape(on: node) {
            let (body, _) = CADFileLoader.shapeToBodyAndMetadata(
                stored, id: "naming-prim-stored",
                color: SIMD4(0.3, 0.6, 1.0, 0.3)
            )
            if let body { bodies.append(body) }
            info += "\nStored shape: retrieved"
        }

        // Query history
        let history = doc.namingHistory(on: node)
        info += "\nHistory entries: \(history.count)"
        for (i, entry) in history.enumerated() {
            info += "\n  [\(i)] \(evolutionName(entry.evolution))"
            info += " old=\(entry.hasOldShape) new=\(entry.hasNewShape)"
        }

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Modification Tracking

    /// Creates a box, then fillets it, recording both steps in the naming graph.
    /// Shows old shape (wireframe) vs new shape (shaded).
    static func modificationTracking() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Modification tracking"

        guard let doc = Document.create(),
              let node = doc.createLabel() else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create document")
        }

        // Step 1: Create original box
        guard let box = Shape.box(width: 4, height: 2, depth: 2) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create box")
        }
        let _ = doc.recordNaming(on: node, evolution: .primitive, newShape: box)

        // Show original box as wireframe (offset left)
        let (origBody, _) = CADFileLoader.shapeToBodyAndMetadata(
            box, id: "naming-mod-original",
            color: SIMD4(0.5, 0.5, 0.5, 0.4)
        )
        if var body = origBody {
            body = offsetViewportBody(body, dx: -5, id: "naming-mod-original")
            bodies.append(body)
        }

        // Step 2: Fillet all edges
        let filleted = box.filleted(radius: 0.3)

        if let filleted {
            // Record modification
            let _ = doc.recordNaming(on: node, evolution: .modify, oldShape: box, newShape: filleted)

            // Show filleted shape (offset right)
            let (newBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                filleted, id: "naming-mod-filleted",
                color: SIMD4(0.2, 0.8, 0.4, 1.0)
            )
            if var body = newBody {
                body = offsetViewportBody(body, dx: 5, id: "naming-mod-filleted")
                bodies.append(body)
            }
            info += "\nFilleted shape created"
        } else {
            info += "\nFillet failed — showing original only"
        }

        // Query history
        let history = doc.namingHistory(on: node)
        info += "\nHistory entries: \(history.count)"
        for (i, entry) in history.enumerated() {
            info += "\n  [\(i)] \(evolutionName(entry.evolution))"
            info += " mod=\(entry.isModification)"
        }

        let evolution = doc.namingEvolution(on: node)
        info += "\nCurrent evolution: \(evolutionName(evolution))"

        // Arrow between old and new
        bodies.append(ViewportBody(
            id: "naming-mod-arrow",
            vertexData: [],
            indices: [],
            edges: [[SIMD3(-2.5, 1, 1), SIMD3(2.5, 1, 1)]],
            color: SIMD4(1.0, 1.0, 0.3, 0.8)
        ))

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Forward/Backward Tracing

    /// Creates shapes, performs boolean operations, and traces the naming graph
    /// forward and backward to show shape lineage.
    static func forwardBackwardTrace() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Forward/backward tracing"

        guard let doc = Document.create(),
              let boxNode = doc.createLabel(),
              let cylNode = doc.createLabel(),
              let resultNode = doc.createLabel() else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create document")
        }

        // Create a box and a cylinder
        guard let box = Shape.box(width: 3, height: 3, depth: 3),
              let cyl = Shape.cylinder(radius: 0.8, height: 4) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create shapes")
        }

        // Record primitives
        let _ = doc.recordNaming(on: boxNode, evolution: .primitive, newShape: box)
        let _ = doc.recordNaming(on: cylNode, evolution: .primitive, newShape: cyl)

        // Show originals (dim, offset apart)
        let (boxBody, _) = CADFileLoader.shapeToBodyAndMetadata(
            box, id: "naming-trace-box", color: SIMD4(0.3, 0.5, 0.8, 0.4)
        )
        if var b = boxBody {
            b = offsetViewportBody(b, dx: -6, id: "naming-trace-box")
            bodies.append(b)
        }

        let (cylBody, _) = CADFileLoader.shapeToBodyAndMetadata(
            cyl, id: "naming-trace-cyl", color: SIMD4(0.8, 0.3, 0.3, 0.4)
        )
        if var b = cylBody {
            b = offsetViewportBody(b, dx: 6, id: "naming-trace-cyl")
            bodies.append(b)
        }

        // Boolean subtraction: box - cylinder → result
        if let result = box.subtracting(cyl) {
            let _ = doc.recordNaming(on: resultNode, evolution: .generated,
                                     oldShape: box, newShape: result)

            let (resBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                result, id: "naming-trace-result",
                color: SIMD4(0.2, 0.8, 0.4, 1.0)
            )
            if let b = resBody { bodies.append(b) }
            info += "\nBoolean result created"

            // Forward trace from box → should find result
            let fwd = doc.tracedForward(from: box, scope: resultNode)
            info += "\nForward from box: \(fwd.count) shape(s)"

            // Backward trace from result → should find box
            let bwd = doc.tracedBackward(from: result, scope: resultNode)
            info += "\nBackward from result: \(bwd.count) shape(s)"
        } else {
            info += "\nBoolean subtraction failed"
        }

        // Arrows showing lineage
        bodies.append(ViewportBody(
            id: "naming-trace-arrow1",
            vertexData: [], indices: [],
            edges: [[SIMD3(-3.5, 1.5, 1.5), SIMD3(-1, 1.5, 1.5)]],
            color: SIMD4(1.0, 1.0, 0.3, 0.6)
        ))
        bodies.append(ViewportBody(
            id: "naming-trace-arrow2",
            vertexData: [], indices: [],
            edges: [[SIMD3(3.5, 1.5, 1.5), SIMD3(1, 1.5, 1.5)]],
            color: SIMD4(1.0, 1.0, 0.3, 0.6)
        ))

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Named Selection Persistence

    /// Demonstrates selecting a sub-shape by name and resolving it after modification.
    static func namedSelection() -> Curve2DGallery.GalleryResult {
        var bodies: [ViewportBody] = []
        var info = "Named selection persistence"

        guard let doc = Document.create(),
              let shapeNode = doc.createLabel(),
              let selNode = doc.createLabel() else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create document")
        }

        // Create a box
        guard let box = Shape.box(width: 4, height: 3, depth: 2) else {
            return Curve2DGallery.GalleryResult(bodies: [], description: "Failed to create box")
        }

        let _ = doc.recordNaming(on: shapeNode, evolution: .primitive, newShape: box)

        // Get a face from the box and "select" it by name
        let faces = box.faces()
        if let face = faces.first, let faceShape = face.fixed() {
            let selected = doc.selectShape(faceShape, context: box, on: selNode)
            info += "\nFace selected: \(selected)"

            // Resolve the selection
            if let resolved = doc.resolveShape(on: selNode) {
                // Show the resolved face as a highlighted body
                let (resBody, _) = CADFileLoader.shapeToBodyAndMetadata(
                    resolved, id: "naming-sel-resolved",
                    color: SIMD4(1.0, 0.4, 0.2, 0.7)
                )
                if let b = resBody { bodies.append(b) }
                info += "\nResolved shape: yes"
            } else {
                info += "\nResolved shape: no"
            }
        } else {
            info += "\nNo face available for selection"
        }

        // Show the full box
        let (boxBody, _) = CADFileLoader.shapeToBodyAndMetadata(
            box, id: "naming-sel-box",
            color: SIMD4(0.3, 0.6, 1.0, 0.5)
        )
        if let b = boxBody { bodies.append(b) }

        return Curve2DGallery.GalleryResult(bodies: bodies, description: info)
    }

    // MARK: - Helpers

    private static func evolutionName(_ evolution: NamingEvolution?) -> String {
        guard let e = evolution else { return "none" }
        switch e {
        case .primitive: return "primitive"
        case .generated: return "generated"
        case .modify: return "modify"
        case .delete: return "delete"
        case .selected: return "selected"
        }
    }

    private static func offsetViewportBody(
        _ body: ViewportBody, dx: Float, id: String
    ) -> ViewportBody {
        let stride = 6
        var newVerts: [Float] = []
        newVerts.reserveCapacity(body.vertexData.count)
        for i in Swift.stride(from: 0, to: body.vertexData.count, by: stride) {
            newVerts.append(body.vertexData[i] + dx)
            newVerts.append(body.vertexData[i + 1])
            newVerts.append(body.vertexData[i + 2])
            newVerts.append(body.vertexData[i + 3])
            newVerts.append(body.vertexData[i + 4])
            newVerts.append(body.vertexData[i + 5])
        }
        let newEdges = body.edges.map { polyline in
            polyline.map { SIMD3($0.x + dx, $0.y, $0.z) }
        }
        return ViewportBody(
            id: id,
            vertexData: newVerts,
            indices: body.indices,
            edges: newEdges,
            faceIndices: body.faceIndices,
            color: body.color
        )
    }
}
