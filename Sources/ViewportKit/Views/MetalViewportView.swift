// MetalViewportView.swift
// ViewportKit
//
// SwiftUI view wrapping MTKView with gesture support for Metal rendering.

import SwiftUI
import simd

/// A 3D viewport view using Metal (parallel to the RealityKit `ViewportView`).
///
/// MetalViewportView provides a complete Metal-based 3D viewing experience with:
/// - Orbit, pan, and zoom gestures
/// - ViewCube for orientation and quick navigation
/// - Shaded and wireframe display modes
///
/// ## Example
///
/// ```swift
/// struct ContentView: View {
///     @StateObject private var controller = ViewportController(configuration: .cad)
///     @State private var bodies: [ViewportBody] = [
///         .box(id: "box", color: SIMD4<Float>(0.5, 0.7, 1.0, 1.0))
///     ]
///
///     var body: some View {
///         MetalViewportView(controller: controller, bodies: $bodies)
///     }
/// }
/// ```
public struct MetalViewportView: View {

    // MARK: - Properties

    @ObservedObject private var controller: ViewportController
    @Binding private var bodies: [ViewportBody]

    @State private var renderer: ViewportRenderer?

    // MARK: - Gesture State

    @State private var lastDragValue: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1.0
    @State private var isPanning: Bool = false

    // MARK: - Initialization

    public init(
        controller: ViewportController,
        bodies: Binding<[ViewportBody]>
    ) {
        self.controller = controller
        self._bodies = bodies
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { _ in
            ZStack {
                metalView
                    #if os(iOS)
                    .overlay { panGestureOverlay }
                    .gesture(orbitGesture)
                    .gesture(zoomGesture)
                    .gesture(doubleTapGesture)
                    #else
                    .gesture(macGestures)
                    .gesture(macMagnifyGesture)
                    #endif

                if controller.showViewCube {
                    viewCubeOverlay
                }
            }
        }
        .onAppear {
            if renderer == nil {
                renderer = ViewportRenderer(controller: controller, bodies: $bodies)
            }
        }
    }

    // MARK: - Metal View

    private var metalView: some View {
        Group {
            if let renderer = renderer {
                MetalViewRepresentable(
                    renderer: renderer,
                    backgroundColor: controller.configuration.backgroundColor
                )
            } else {
                Color(
                    red: Double(controller.configuration.backgroundColor.x),
                    green: Double(controller.configuration.backgroundColor.y),
                    blue: Double(controller.configuration.backgroundColor.z)
                )
            }
        }
    }

    // MARK: - iOS Gestures

    #if os(iOS)
    private var panGestureOverlay: some View {
        TwoFingerPanGestureView(
            onChanged: { translation in
                isPanning = true
                controller.handlePan(translation: translation)
            },
            onEnded: { velocity in
                controller.endPan(velocity: velocity)
            }
        )
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !isPanning else { return }

                let delta = CGSize(
                    width: value.translation.width - lastDragValue.width,
                    height: value.translation.height - lastDragValue.height
                )
                lastDragValue = value.translation

                controller.handleOrbit(translation: delta)
            }
            .onEnded { value in
                lastDragValue = .zero
                if !isPanning {
                    controller.endOrbit(velocity: value.velocity)
                }
                isPanning = false
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                lastMagnification = value.magnification
                controller.handleZoom(magnification: delta)
            }
            .onEnded { _ in
                lastMagnification = 1.0
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                controller.reset(animated: true)
            }
    }
    #endif

    // MARK: - macOS Gestures

    #if os(macOS)
    private var macGestures: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDragValue.width,
                    height: value.translation.height - lastDragValue.height
                )
                lastDragValue = value.translation

                let modifiers = NSEvent.modifierFlags

                if modifiers.contains(.shift) {
                    controller.handlePan(translation: delta)
                } else if modifiers.contains(.option) {
                    let zoomDelta = 1.0 + delta.height * 0.01
                    controller.handleZoom(magnification: zoomDelta)
                } else {
                    controller.handleOrbit(translation: delta)
                }
            }
            .onEnded { value in
                lastDragValue = .zero
                controller.endOrbit(velocity: value.velocity)
            }
    }

    private var macMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                lastMagnification = value.magnification
                controller.handleZoom(magnification: delta)
            }
            .onEnded { _ in
                lastMagnification = 1.0
            }
    }
    #endif

    // MARK: - ViewCube Overlay

    private var viewCubeOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ViewCubeView(controller: controller)
                    .frame(width: 80, height: 80)
                    .padding(12)
            }
        }
    }
}

// MARK: - iOS Two-Finger Pan Gesture (Metal version)

#if os(iOS)
import UIKit

/// A transparent UIView overlay that recognizes two-finger pan gestures via UIKit.
private struct TwoFingerPanGestureView: UIViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    @MainActor
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGSize) -> Void
        var onEnded: (CGSize) -> Void

        init(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping (CGSize) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .changed:
                let translation = recognizer.translation(in: recognizer.view)
                onChanged(CGSize(width: translation.x, height: translation.y))
                recognizer.setTranslation(.zero, in: recognizer.view)
            case .ended, .cancelled:
                let velocity = recognizer.velocity(in: recognizer.view)
                onEnded(CGSize(width: velocity.x, height: velocity.y))
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif
