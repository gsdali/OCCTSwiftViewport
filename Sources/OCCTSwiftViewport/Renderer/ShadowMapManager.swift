// ShadowMapManager.swift
// ViewportKit
//
// Manages the depth texture used for shadow mapping.

import Metal

@MainActor
final class ShadowMapManager {

    private let device: MTLDevice
    private(set) var texture: MTLTexture?
    private(set) var size: Int = 0

    init(device: MTLDevice) {
        self.device = device
    }

    /// Ensures the shadow map matches the given size, recreating if necessary.
    func ensureSize(_ newSize: Int) {
        guard newSize > 0 else { return }
        guard newSize != size else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: newSize,
            height: newSize,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        texture = device.makeTexture(descriptor: desc)
        size = newSize
    }
}
