// PickResult.swift
// ViewportKit
//
// Decoded GPU pick result from the pick ID buffer.

import Foundation

/// Result of a GPU-accelerated pick operation.
///
/// Decodes the raw R32Uint value from the pick ID buffer into a body ID
/// and triangle index. The encoding is `objectIndex | (primitiveID << 16)`,
/// giving 16 bits for each.
public struct PickResult: Sendable, Equatable {

    /// Sentinel value indicating no hit (background or non-pickable overlay).
    public static let sentinel: UInt32 = 0xFFFF_FFFF

    /// The ID string of the picked body.
    public let bodyID: String

    /// The zero-based index of the body in the draw order.
    public let bodyIndex: Int

    /// The primitive (triangle) index within the body's geometry.
    public let triangleIndex: Int

    /// The raw encoded value read from the pick buffer.
    public let rawValue: UInt32

    /// The pick layer the body belongs to. Used by `ViewportController` to
    /// route the result to either `pickResult` or `widgetPickResult`.
    public let pickLayer: PickLayer

    /// Decodes a raw pick value using the provided index map.
    ///
    /// - Parameters:
    ///   - rawValue: The R32Uint value read back from the GPU.
    ///   - indexMap: Mapping from objectIndex (Int) to body ID (String).
    ///   - layerMap: Optional mapping from body ID to its `PickLayer`. Bodies
    ///     not present in the map are treated as `.userGeometry`.
    /// - Returns: `nil` if the raw value is the sentinel (no hit) or the
    ///   object index is not found in the map.
    public init?(rawValue: UInt32, indexMap: [Int: String], layerMap: [String: PickLayer] = [:]) {
        guard rawValue != Self.sentinel else { return nil }

        let objectIndex = Int(rawValue & 0xFFFF)
        let primitiveID = Int(rawValue >> 16)

        guard let bodyID = indexMap[objectIndex] else { return nil }

        self.bodyID = bodyID
        self.bodyIndex = objectIndex
        self.triangleIndex = primitiveID
        self.rawValue = rawValue
        self.pickLayer = layerMap[bodyID] ?? .userGeometry
    }
}
