// PickTextureManager.swift
// ViewportKit
//
// Manages the R32Uint pick ID texture used as a second color attachment.

import Metal

/// Owns and recreates the R32Uint pick ID texture when the drawable size changes.
@MainActor
final class PickTextureManager {

    private let device: MTLDevice
    private(set) var texture: MTLTexture?
    private(set) var width: Int = 0
    private(set) var height: Int = 0

    init(device: MTLDevice) {
        self.device = device
    }

    /// Ensures the pick texture matches the given size, recreating if necessary.
    ///
    /// - Parameters:
    ///   - newWidth: Drawable width in pixels.
    ///   - newHeight: Drawable height in pixels.
    func ensureSize(width newWidth: Int, height newHeight: Int) {
        guard newWidth > 0, newHeight > 0 else { return }
        guard newWidth != width || newHeight != height else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Uint,
            width: newWidth,
            height: newHeight,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        texture = device.makeTexture(descriptor: desc)
        width = newWidth
        height = newHeight
    }
}
