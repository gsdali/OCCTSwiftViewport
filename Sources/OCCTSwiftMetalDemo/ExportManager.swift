// ExportManager.swift
// OCCTSwiftMetalDemo
//
// Wraps OCCTSwift export functionality for OBJ and PLY formats.

import Foundation
import OCCTSwift

/// Supported export formats.
enum ExportFormat: String, CaseIterable, Sendable {
    case obj = "OBJ"
    case ply = "PLY"

    var fileExtension: String {
        rawValue.lowercased()
    }
}

/// Manages exporting shapes to mesh file formats.
enum ExportManager {

    /// Exports shapes to the specified format.
    ///
    /// For multiple shapes, each is exported to a numbered file in the same directory.
    static func export(
        shapes: [Shape],
        format: ExportFormat,
        to url: URL,
        deflection: Double = 0.1
    ) async throws {
        try await Task.detached {
            try exportSync(shapes: shapes, format: format, to: url, deflection: deflection)
        }.value
    }

    private static func exportSync(
        shapes: [Shape],
        format: ExportFormat,
        to url: URL,
        deflection: Double
    ) throws {
        guard !shapes.isEmpty else { return }

        if shapes.count == 1 {
            try exportShape(shapes[0], format: format, to: url, deflection: deflection)
        } else {
            // Multiple shapes: number each output file
            let base = url.deletingPathExtension()
            let ext = url.pathExtension.isEmpty ? format.fileExtension : url.pathExtension
            for (i, shape) in shapes.enumerated() {
                let numbered = base.appendingPathExtension("\(i).\(ext)")
                try exportShape(shape, format: format, to: numbered, deflection: deflection)
            }
        }
    }

    private static func exportShape(
        _ shape: Shape,
        format: ExportFormat,
        to url: URL,
        deflection: Double
    ) throws {
        switch format {
        case .obj:
            try Exporter.writeOBJ(shape: shape, to: url, deflection: deflection)
        case .ply:
            try Exporter.writePLY(shape: shape, to: url, deflection: deflection)
        }
    }
}
