// ScriptManifest.swift
// OCCTSwiftMetalDemo
//
// JSON manifest format for script harness output.

import Foundation
import simd

/// Manifest written by the script harness, read by the demo app.
struct ScriptManifest: Codable, Sendable {
    let version: Int
    let timestamp: Date
    let description: String?
    let bodies: [BodyDescriptor]

    struct BodyDescriptor: Codable, Sendable {
        let id: String?
        let file: String
        let format: String
        let name: String?
        let roughness: Float?
        let metallic: Float?

        // Color stored as [r, g, b, a] array for JSON compatibility
        private let colorArray: [Float]?

        var color: SIMD4<Float>? {
            guard let c = colorArray, c.count >= 4 else { return nil }
            return SIMD4<Float>(c[0], c[1], c[2], c[3])
        }

        enum CodingKeys: String, CodingKey {
            case id, file, format, name, roughness, metallic
            case colorArray = "color"
        }
    }
}
