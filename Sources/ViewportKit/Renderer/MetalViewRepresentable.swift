// MetalViewRepresentable.swift
// ViewportKit
//
// Platform-specific MTKView wrapper for SwiftUI.

import SwiftUI
import MetalKit

#if os(iOS)

/// iOS wrapper for MTKView.
struct MetalViewRepresentable: UIViewRepresentable {
    let renderer: ViewportRenderer
    let backgroundColor: SIMD4<Float>

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = renderer.metalDevice
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = mtlClearColor(from: backgroundColor)
        view.preferredFramesPerSecond = 60
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.clearColor = mtlClearColor(from: backgroundColor)
    }
}

#elseif os(macOS)

/// MTKView subclass that captures scroll wheel events on macOS.
class ScrollCaptureMTKView: MTKView {
    var onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        let locationInView = convert(event.locationInWindow, from: nil)
        let viewSize = bounds.size
        onScrollWheel?(CGFloat(delta), locationInView, viewSize)
    }
}

/// macOS wrapper for MTKView.
struct MetalViewRepresentable: NSViewRepresentable {
    let renderer: ViewportRenderer
    let backgroundColor: SIMD4<Float>
    var onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?

    func makeNSView(context: Context) -> MTKView {
        let view = ScrollCaptureMTKView()
        view.device = renderer.metalDevice
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = mtlClearColor(from: backgroundColor)
        view.preferredFramesPerSecond = 60
        view.onScrollWheel = onScrollWheel
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.clearColor = mtlClearColor(from: backgroundColor)
        (nsView as? ScrollCaptureMTKView)?.onScrollWheel = onScrollWheel
    }
}

#endif

// MARK: - Helpers

private func mtlClearColor(from color: SIMD4<Float>) -> MTLClearColor {
    MTLClearColor(
        red: Double(color.x),
        green: Double(color.y),
        blue: Double(color.z),
        alpha: Double(color.w)
    )
}
