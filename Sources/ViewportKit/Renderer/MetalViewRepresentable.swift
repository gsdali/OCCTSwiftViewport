// MetalViewRepresentable.swift
// ViewportKit
//
// Platform-specific MTKView wrapper for SwiftUI.

import SwiftUI
import MetalKit

#if os(iOS)
import UIKit

/// MTKView subclass that captures tap gestures on iOS.
class TapCaptureMTKView: MTKView {
    var onTap: ((CGPoint, CGSize) -> Void)?

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        onTap?(location, bounds.size)
    }
}

/// iOS wrapper for MTKView.
struct MetalViewRepresentable: UIViewRepresentable {
    let renderer: ViewportRenderer
    let backgroundColor: SIMD4<Float>
    var onTap: ((CGPoint, CGSize) -> Void)?

    func makeUIView(context: Context) -> MTKView {
        let view = TapCaptureMTKView(frame: .zero, device: renderer.metalDevice)
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = mtlClearColor(from: backgroundColor)
        view.preferredFramesPerSecond = 60
        view.isMultipleTouchEnabled = true
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.clearColor = mtlClearColor(from: backgroundColor)
        (uiView as? TapCaptureMTKView)?.onTap = onTap
    }
}

#elseif os(macOS)

/// MTKView subclass that captures scroll wheel and mouse-down events on macOS.
class ScrollCaptureMTKView: MTKView {
    var onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    var onMouseDown: ((CGPoint, CGSize) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        let locationInView = convert(event.locationInWindow, from: nil)
        let viewSize = bounds.size
        onScrollWheel?(CGFloat(delta), locationInView, viewSize)
    }

    override func mouseDown(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        let viewSize = bounds.size
        onMouseDown?(locationInView, viewSize)
        super.mouseDown(with: event)
    }
}

/// macOS wrapper for MTKView.
struct MetalViewRepresentable: NSViewRepresentable {
    let renderer: ViewportRenderer
    let backgroundColor: SIMD4<Float>
    var onScrollWheel: ((CGFloat, CGPoint, CGSize) -> Void)?
    var onMouseDown: ((CGPoint, CGSize) -> Void)?

    func makeNSView(context: Context) -> MTKView {
        let view = ScrollCaptureMTKView()
        view.device = renderer.metalDevice
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = mtlClearColor(from: backgroundColor)
        view.preferredFramesPerSecond = 60
        view.onScrollWheel = onScrollWheel
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.clearColor = mtlClearColor(from: backgroundColor)
        if let scView = nsView as? ScrollCaptureMTKView {
            scView.onScrollWheel = onScrollWheel
            scView.onMouseDown = onMouseDown
        }
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
