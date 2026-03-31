// ScriptManifest.swift
// OCCTSwiftTools
//
// JSON manifest format for script harness output.

import Foundation
import simd

/// Manifest written by the script harness, read by consumers.
public struct ScriptManifest: Codable, Sendable {
    public let version: Int
    public let timestamp: Date
    public let description: String?
    public let bodies: [BodyDescriptor]
    public let metadata: ManifestMetadata?

    public struct BodyDescriptor: Codable, Sendable {
        public let id: String?
        public let file: String
        public let format: String
        public let name: String?
        public let roughness: Float?
        public let metallic: Float?

        // Color stored as [r, g, b, a] array for JSON compatibility
        private let colorArray: [Float]?

        public var color: SIMD4<Float>? {
            guard let c = colorArray, c.count >= 4 else { return nil }
            return SIMD4<Float>(c[0], c[1], c[2], c[3])
        }

        enum CodingKeys: String, CodingKey {
            case id, file, format, name, roughness, metallic
            case colorArray = "color"
        }
    }

    public struct ManifestMetadata: Codable, Sendable {
        public let name: String
        public let revision: String?
        public let dateCreated: Date?
        public let dateModified: Date?
        public let source: String?
        public let tags: [String]?
        public let notes: String?
    }
}
