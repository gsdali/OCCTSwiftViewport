// PickingConfiguration.swift
// ViewportKit
//
// Configuration for GPU-accelerated picking.

import Foundation

/// Configuration for the GPU pick ID buffer system.
public struct PickingConfiguration: Sendable {

    /// Whether picking is enabled. When `false`, the pick texture is not
    /// allocated and the second color attachment is not used.
    public var isEnabled: Bool

    /// Creates a picking configuration.
    ///
    /// - Parameter isEnabled: Whether picking is active. Defaults to `false`.
    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}
