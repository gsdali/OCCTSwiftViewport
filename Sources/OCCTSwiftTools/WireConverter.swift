// WireConverter.swift
// OCCTSwiftTools
//
// Converts OCCTSwift Wire objects to ViewportBody for rendering.

import simd
import OCCTSwift
import OCCTSwiftViewport

/// Converts OCCTSwift Wire objects to edge-only ViewportBody values.
public enum WireConverter {

    /// Converts a Wire to an edge-only ViewportBody by extracting ordered edge polylines.
    public static func wireToBody(
        _ wire: Wire,
        id: String,
        color: SIMD4<Float>
    ) -> ViewportBody {
        let edgeCount = wire.orderedEdgeCount
        var polylines: [[SIMD3<Float>]] = []

        for i in 0..<edgeCount {
            if let pts = wire.orderedEdgePoints(at: i, maxPoints: 10000) {
                let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
                if floatPts.count >= 2 {
                    polylines.append(floatPts)
                }
            }
        }

        // Fallback: if orderedEdgePoints didn't work, wrap as Shape for edge extraction
        if polylines.isEmpty, let shape = Shape.fromWire(wire) {
            let count = shape.edgeCount
            for i in 0..<count {
                if let pts = shape.edgePolyline(at: i, deflection: 0.005) {
                    let floatPts = pts.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
                    if floatPts.count >= 2 {
                        polylines.append(floatPts)
                    }
                }
            }
        }

        return ViewportBody(
            id: id, vertexData: [], indices: [],
            edges: polylines, color: color
        )
    }
}
