// BoundingBox.swift
// ViewportKit
//
// Axis-aligned bounding box value type.

import simd

/// An axis-aligned bounding box (AABB).
public struct BoundingBox: Hashable, Sendable {

    /// Minimum corner.
    public var min: SIMD3<Float>

    /// Maximum corner.
    public var max: SIMD3<Float>

    /// Center point of the box.
    public var center: SIMD3<Float> {
        (min + max) * 0.5
    }

    /// Size along each axis.
    public var size: SIMD3<Float> {
        max - min
    }

    /// Length of the diagonal.
    public var diagonalLength: Float {
        simd_length(size)
    }

    /// Creates a bounding box from minimum and maximum corners.
    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    /// Returns the smallest box enclosing both `self` and `other`.
    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            min: simd_min(self.min, other.min),
            max: simd_max(self.max, other.max)
        )
    }
}
