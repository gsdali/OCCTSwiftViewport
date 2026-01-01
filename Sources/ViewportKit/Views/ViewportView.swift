// ViewportView.swift
// ViewportKit
//
// Main SwiftUI view for 3D viewport using RealityKit.

import SwiftUI
import RealityKit
import simd

/// A 3D viewport view using RealityKit.
///
/// ViewportView provides a complete 3D viewing experience with:
/// - Orbit, pan, and zoom gestures
/// - ViewCube for orientation and quick navigation
/// - Configurable display modes and lighting
///
/// ## Example
///
/// ```swift
/// struct ContentView: View {
///     @StateObject private var controller = ViewportController()
///
///     var body: some View {
///         ViewportView(controller: controller, entities: [
///             makeBox()
///         ])
///     }
///
///     func makeBox() -> Entity {
///         ModelEntity(
///             mesh: .generateBox(size: 1),
///             materials: [SimpleMaterial(color: .gray, isMetallic: true)]
///         )
///     }
/// }
/// ```
public struct ViewportView: View {

    // MARK: - Properties

    @ObservedObject private var controller: ViewportController

    /// Entities to display in the viewport.
    private let entities: [Entity]

    // MARK: - Gesture State

    @State private var lastDragValue: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1.0
    @State private var isOrbiting: Bool = false
    @State private var isPanning: Bool = false

    // MARK: - Initialization

    /// Creates a viewport view with the specified controller and entities.
    ///
    /// - Parameters:
    ///   - controller: The viewport controller managing state
    ///   - entities: Entities to display in the scene
    public init(
        controller: ViewportController,
        entities: [Entity] = []
    ) {
        self.controller = controller
        self.entities = entities
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                realityView

                // ViewCube overlay
                if controller.showViewCube {
                    viewCubeOverlay
                }
            }
        }
    }

    // MARK: - RealityView

    private var realityView: some View {
        RealityView { content in
            // Set to virtual camera mode (non-AR)
            content.camera = .virtual

            // Create and configure camera entity
            let cameraEntity = PerspectiveCamera()
            cameraEntity.camera.fieldOfViewInDegrees = controller.cameraState.fieldOfView
            content.add(cameraEntity)
            controller.cameraEntity = cameraEntity

            // Set up lighting
            setupLighting(content: content)

            // Add ground grid if enabled
            if controller.showGrid {
                addGroundGrid(content: content)
            }

            // Add coordinate axes if enabled
            if controller.showAxes {
                addCoordinateAxes(content: content)
            }

            // Add user-provided entities
            for entity in entities {
                content.add(entity)
            }

        } update: { content in
            // Update camera transform from controller state
            if let camera = controller.cameraEntity {
                camera.transform = controller.cameraState.transform
            }
        }
        #if os(iOS)
        .gesture(orbitGesture)
        .gesture(zoomGesture)
        .gesture(doubleTapGesture)
        #else
        .gesture(macGestures)
        .gesture(macMagnifyGesture)
        #endif
    }

    // MARK: - iOS Gestures

    #if os(iOS)
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDragValue.width,
                    height: value.translation.height - lastDragValue.height
                )
                lastDragValue = value.translation

                // Check for two-finger drag (pan) vs one-finger (orbit)
                controller.handleOrbit(translation: delta)
            }
            .onEnded { value in
                lastDragValue = .zero
                controller.endOrbit(velocity: value.velocity)
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

                // Check modifier keys
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

    // MARK: - Scene Setup

    @MainActor
    private func setupLighting(content: RealityViewCameraContent) {
        let lighting = controller.configuration.lightingConfiguration

        // Key light
        if lighting.keyLight.isEnabled {
            let keyLight = DirectionalLight()
            keyLight.light.intensity = lighting.keyLight.intensity * 1000
            keyLight.light.color = platformColor(from: lighting.keyLight.color)
            keyLight.look(
                at: .zero,
                from: -lighting.keyLight.direction * 10,
                relativeTo: nil
            )
            if lighting.shadowsEnabled {
                keyLight.shadow = DirectionalLightComponent.Shadow()
            }
            content.add(keyLight)
        }

        // Fill light
        if lighting.fillLight.isEnabled {
            let fillLight = DirectionalLight()
            fillLight.light.intensity = lighting.fillLight.intensity * 1000
            fillLight.light.color = platformColor(from: lighting.fillLight.color)
            fillLight.look(
                at: .zero,
                from: -lighting.fillLight.direction * 10,
                relativeTo: nil
            )
            content.add(fillLight)
        }

        // Back light
        if lighting.backLight.isEnabled {
            let backLight = DirectionalLight()
            backLight.light.intensity = lighting.backLight.intensity * 1000
            backLight.light.color = platformColor(from: lighting.backLight.color)
            backLight.look(
                at: .zero,
                from: -lighting.backLight.direction * 10,
                relativeTo: nil
            )
            content.add(backLight)
        }
    }

    private func platformColor(from simd: SIMD3<Float>) -> PlatformColor {
        #if os(iOS)
        return UIColor(red: CGFloat(simd.x), green: CGFloat(simd.y), blue: CGFloat(simd.z), alpha: 1)
        #else
        return NSColor(red: CGFloat(simd.x), green: CGFloat(simd.y), blue: CGFloat(simd.z), alpha: 1)
        #endif
    }

    @MainActor
    private func addGroundGrid(content: RealityViewCameraContent) {
        // Create a simple ground plane
        // In a full implementation, this would be a proper grid with lines
        let ground = ModelEntity(
            mesh: .generatePlane(width: 100, depth: 100),
            materials: [SimpleMaterial(color: .init(white: 0.9, alpha: 1), isMetallic: false)]
        )
        ground.position = SIMD3<Float>(0, 0, -0.01) // Slightly below origin
        content.add(ground)
    }

    @MainActor
    private func addCoordinateAxes(content: RealityViewCameraContent) {
        let axisLength: Float = 2.0
        let axisRadius: Float = 0.02

        // X axis (red)
        let xAxis = ModelEntity(
            mesh: .generateCylinder(height: axisLength, radius: axisRadius),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        xAxis.position = SIMD3<Float>(axisLength / 2, 0, 0)
        xAxis.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        content.add(xAxis)

        // Y axis (green)
        let yAxis = ModelEntity(
            mesh: .generateCylinder(height: axisLength, radius: axisRadius),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        yAxis.position = SIMD3<Float>(0, axisLength / 2, 0)
        content.add(yAxis)

        // Z axis (blue)
        let zAxis = ModelEntity(
            mesh: .generateCylinder(height: axisLength, radius: axisRadius),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        zAxis.position = SIMD3<Float>(0, 0, axisLength / 2)
        zAxis.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        content.add(zAxis)
    }
}

// MARK: - Platform Color Type

#if os(iOS)
private typealias PlatformColor = UIColor
#else
private typealias PlatformColor = NSColor
#endif
